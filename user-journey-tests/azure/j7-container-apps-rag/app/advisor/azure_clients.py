"""azure_clients.py — the single funnel for EVERY Azure SDK call the explainer makes.

Keep any new Azure call in this module so call sites stay grep-able.

Intended GCP mapping (planning notes, per service):
  Azure OpenAI account car-openai-<uniq>     -> Vertex AI. Not a drop-in: see the
                                                note under openai_client() below
  AI Search index `fund-docs`                -> Vertex AI Search, or an embedding
                                                index we run ourselves. Open question
  Cosmos DB SQL container `chat-history`     -> Firestore, on the document shape
  Blob container `docs` on cardocs<uniq>     -> Cloud Storage, same object keys
  System-assigned managed identity           -> service account + ADC
  Application Insights connection string     -> Cloud Trace / Cloud Monitoring via
                                                OpenTelemetry
  Private endpoints on the model account and
  the search service                         -> Private Service Connect endpoints

Credentials: none are configured here. On Container Apps the app's
system-assigned identity is what DefaultAzureCredential picks up, from the
IDENTITY_ENDPOINT and IDENTITY_HEADER pair the platform injects. Running the
same code on a laptop, the same class falls back to whoever is signed in to the
Azure CLI.

Nothing in this module raises on a service being unreachable, and nothing in it
waits indefinitely. Every entry point returns an (ok, detail) shape or a safe
default, and every call that leaves the process has a deadline, because /health
and /admin/azure-check have to answer even when a dependency is down. Answering
late is the same as not answering: the platform calls a health endpoint on a
timer and restarts the container when it does not reply in time.
"""

from __future__ import annotations

import functools
import os
import threading
from typing import Any

from azure.core.exceptions import ResourceNotFoundError
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchableField,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SimpleField,
)
from azure.storage.blob import BlobServiceClient
from openai import AzureOpenAI

# --- configuration ----------------------------------------------------------

OPENAI_ENDPOINT = os.environ.get("CAR_OPENAI_ENDPOINT", "")

# The name of the DEPLOYMENT created on the account, not the name of the model.
# Azure OpenAI routes by deployment; the model behind it is chosen when the
# deployment is made and the caller never names it.
OPENAI_DEPLOYMENT = os.environ.get("CAR_OPENAI_DEPLOYMENT", "explainer")

# Azure OpenAI pins the wire contract to a dated API version, separately from
# the client library version. Changing it changes which request and response
# fields exist.
OPENAI_API_VERSION = os.environ.get("CAR_OPENAI_API_VERSION", "2024-10-21")

SEARCH_ENDPOINT = os.environ.get("CAR_SEARCH_ENDPOINT", "")
SEARCH_INDEX = os.environ.get("CAR_SEARCH_INDEX", "fund-docs")

COSMOS_ENDPOINT = os.environ.get("CAR_COSMOS_ENDPOINT", "")
COSMOS_DATABASE = os.environ.get("CAR_COSMOS_DATABASE", "explainer")
COSMOS_CONTAINER = os.environ.get("CAR_COSMOS_CONTAINER", "chat-history")

DOCS_ACCOUNT = os.environ.get("CAR_DOCS_ACCOUNT", "")
DOCS_CONTAINER = os.environ.get("CAR_DOCS_CONTAINER", "docs")
_DOCS_BLOB_ENDPOINT = os.environ.get("CAR_DOCS_BLOB_ENDPOINT") or (
    f"https://{DOCS_ACCOUNT}.blob.core.windows.net/" if DOCS_ACCOUNT else ""
)

# Scope for a token that Azure OpenAI accepts. Note it is the general Cognitive
# Services audience, not an OpenAI-specific one.
_COGNITIVE_SERVICES_SCOPE = "https://cognitiveservices.azure.com/.default"

# The platform injects this into every replica; it is where the managed identity
# hands out tokens. The identity probe names it in its own failure detail on
# purpose. This address is on the container itself, so a probe that cannot get
# an answer out of it has found a problem inside the process, no matter what the
# probes that cross the network are saying at the same time.
IDENTITY_ENDPOINT = os.environ.get("IDENTITY_ENDPOINT", "")

# --- time budgets -------------------------------------------------------------
# Two services here answer only on a private endpoint. When that path is not
# working the socket does not get refused, it goes nowhere, and a client left on
# its library defaults waits on it for minutes. Every client below therefore
# carries an explicit connect and read timeout, and every probe carries a hard
# wall-clock deadline on top, so an unreachable dependency is reported as
# unreachable instead of hanging the endpoint that reports it.
_CONNECT_TIMEOUT = 3
_READ_TIMEOUT = 10
# The model is the one call worth waiting on: a completion legitimately takes
# longer than any of the above. Probing the account is not a completion, so
# probe_openai overrides this per request.
_MODEL_TIMEOUT = 60

# Longer than a connect and a read put together, and longer again by the token
# acquisition that precedes them on the first call of a replica's life. The
# outer deadline is a backstop for calls that hang, not a competitor to the
# per-request timeouts: set it below them and it fires first every time, and
# every failure reports the same shrug instead of the specific thing the SDK was
# about to say. Whichever budget is shorter is the one that writes the detail.
_PROBE_DEADLINE = 20
_DATA_DEADLINE = 25


_UNSET = object()


def _host(url: str) -> str:
    """Just the host out of a configured endpoint, for saying what was waited on."""
    return url.split("://", 1)[-1].split("/", 1)[0] or url


def _failed(exc: BaseException) -> str:
    """Type and first line of a failure, short enough to sit in a JSON field.

    The type on its own does not separate "the name never resolved" from "the
    name resolved and the service refused us", and those two have entirely
    different fixes. The message is where that distinction lives.
    """
    message = " ".join(str(exc).split())
    return f"{type(exc).__name__}: {message[:180]}" if message else type(exc).__name__


def _bounded(
    seconds: int = _PROBE_DEADLINE, on_timeout: Any = _UNSET, waits_on: str = ""
):
    """Give one call a hard wall-clock deadline.

    The SDK timeouts above bound a single request each. They do not bound a call
    chain — acquiring a token happens inside the call and carries its own
    budget, and a credential with nothing to talk to can spend minutes working
    through its sources before it gives up. This bounds the whole chain from
    outside, so every entry point in this module has an upper bound in seconds
    rather than an upper bound in principle.

    `on_timeout` is what the caller gets when the deadline passes; pass a
    callable for anything mutable. Probes default to the same (ok, detail) shape
    they use for every other failure, so a timeout reads as one more thing that
    did not answer. `waits_on` names the address the call was waiting on, which
    is what turns "no answer" into something anyone can act on: an address on
    this container and an address across the network fail identically here and
    have nothing else in common.

    The worker is a daemon thread and the deadline abandons it rather than
    stopping it — there is no way to stop it. So nothing this decorator wraps
    may hold a lock that anything else needs; an abandoned worker keeps whatever
    it was holding for the life of the process. See _shared below.
    """

    def decorate(call):
        @functools.wraps(call)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            outcome: dict[str, Any] = {}

            def run() -> None:
                try:
                    outcome["value"] = call(*args, **kwargs)
                except Exception as exc:  # noqa: BLE001
                    outcome["failed"] = exc

            worker = threading.Thread(target=run, daemon=True)
            worker.start()
            worker.join(seconds)
            timed_out = worker.is_alive()

            if on_timeout is _UNSET:
                if timed_out:
                    waited = f"no answer within {seconds}s"
                    return {
                        "ok": False,
                        "detail": f"{waited} from {waits_on}" if waits_on else waited,
                        "waited_on": waits_on,
                    }
                if "failed" in outcome:
                    return {"ok": False, "detail": _failed(outcome["failed"])}
                return outcome.get("value", {"ok": False, "detail": "no result"})

            if timed_out or "failed" in outcome:
                return on_timeout() if callable(on_timeout) else on_timeout
            return outcome["value"]

        return wrapper

    return decorate


_lock = threading.Lock()
_clients: dict[str, Any] = {}


def _shared(name: str, build: Any) -> Any:
    """The one instance of `name` for this process, built at most once.

    Two rules, and the second one is why this is a function rather than a
    `with _lock:` in each factory below.

    Build outside the lock, publish inside it. Every builder here reaches for a
    credential and some of them reach the service — CosmosClient talks to the
    account before its constructor returns — so a lock held for the length of a
    build is a lock held for the length of a network call. Worse, _bounded
    abandons a worker that overruns its deadline, and an abandoned worker never
    gives a lock back: one slow dependency would take every unrelated client in
    the module down with it, permanently, and each would report only that it did
    not answer in time.

    Never take the lock while already holding it. threading.Lock is not
    reentrant, so a builder that called something which locks — get_credential,
    say — would block on itself forever with no exception and no traceback,
    which looks exactly like a dependency being slow. Keeping the lock down to a
    single dict write is what makes that structurally impossible rather than
    merely avoided.

    Two threads racing here build twice and throw one away. That costs a client
    object; the alternative costs the process.
    """
    existing = _clients.get(name)
    if existing is not None:
        return existing
    built = build()
    with _lock:
        return _clients.setdefault(name, built)


def get_credential() -> DefaultAzureCredential:
    """One credential for the whole process; the SDK caches tokens behind it.

    Constructing the credential does not reach the network — acquiring a token
    does, and every caller below is prepared for that to fail.
    """
    return _shared("credential", DefaultAzureCredential)


# --- the model ---------------------------------------------------------------


def openai_client() -> AzureOpenAI | None:
    """Client for the model account, or None when no endpoint is configured.

    Three things about this construction are Azure-shaped rather than
    OpenAI-shaped, and all three are load-bearing:

      * azure_endpoint is the account's own host. There is no global service
        host to fall back to.
      * api_version pins the dated wire contract. It is not the library version
        and it is not optional.
      * requests address a deployment name, not a model id — see chat() below.

    Account keys are switched off on this account, so the credential is an Entra
    token. get_bearer_token_provider hands the client a callable rather than a
    string so the token is re-fetched when it expires; a client built with a
    literal token stops working roughly an hour after start-up.
    """
    if not OPENAI_ENDPOINT:
        return None

    def build() -> AzureOpenAI:
        token_provider = get_bearer_token_provider(
            get_credential(), _COGNITIVE_SERVICES_SCOPE
        )
        return AzureOpenAI(
            azure_endpoint=OPENAI_ENDPOINT,
            api_version=OPENAI_API_VERSION,
            azure_ad_token_provider=token_provider,
            timeout=_MODEL_TIMEOUT,
            max_retries=1,
        )

    try:
        return _shared("openai", build)
    except Exception:
        return None


def chat(messages: list[dict[str, str]], max_tokens: int = 500) -> str:
    """One chat completion against the deployment.

    `model` carries the DEPLOYMENT name. On this platform that parameter selects
    a deployment on this account; it is not a model identifier and there is no
    catalogue of values it accepts beyond what has been deployed here.
    """
    client = openai_client()
    if client is None:
        raise RuntimeError("no model endpoint configured")
    response = client.chat.completions.create(
        model=OPENAI_DEPLOYMENT,
        messages=messages,
        max_tokens=max_tokens,
        temperature=0.2,
    )
    return response.choices[0].message.content or ""


# --- retrieval ---------------------------------------------------------------


def search_client() -> SearchClient | None:
    """Document-level client: query the index, upload into it."""
    if not SEARCH_ENDPOINT:
        return None
    try:
        return _shared(
            "search",
            lambda: SearchClient(
                endpoint=SEARCH_ENDPOINT,
                index_name=SEARCH_INDEX,
                credential=get_credential(),
                connection_timeout=_CONNECT_TIMEOUT,
                read_timeout=_READ_TIMEOUT,
                retry_total=0,
            ),
        )
    except Exception:
        return None


def search_index_client() -> SearchIndexClient | None:
    """Definition-level client: create or update the index itself.

    A separate client and a separate grant — the role that manages index
    definitions cannot load documents, and the role that loads documents cannot
    change a definition.
    """
    if not SEARCH_ENDPOINT:
        return None
    try:
        return _shared(
            "search-index",
            lambda: SearchIndexClient(
                endpoint=SEARCH_ENDPOINT,
                credential=get_credential(),
                connection_timeout=_CONNECT_TIMEOUT,
                read_timeout=_READ_TIMEOUT,
                retry_total=0,
            ),
        )
    except Exception:
        return None


@_bounded(30, on_timeout=False)
def ensure_index() -> bool:
    """Create the index if it is not there yet. Idempotent, never raises."""
    client = search_index_client()
    if client is None:
        return False
    index = SearchIndex(
        name=SEARCH_INDEX,
        fields=[
            SimpleField(name="id", type=SearchFieldDataType.String, key=True),
            SearchableField(name="title", type=SearchFieldDataType.String),
            SearchableField(name="content", type=SearchFieldDataType.String),
            SearchField(
                name="fund",
                type=SearchFieldDataType.String,
                filterable=True,
                facetable=True,
            ),
        ],
    )
    try:
        client.create_or_update_index(index)
        return True
    except Exception:
        return False


@_bounded(30, on_timeout=lambda: 0)
def upload_documents(documents: list[dict[str, Any]]) -> int:
    """Push documents into the index. Returns how many the service accepted."""
    client = search_client()
    if client is None:
        return 0
    try:
        results = client.upload_documents(documents=documents)
        return sum(1 for r in results if r.succeeded)
    except Exception:
        return 0


@_bounded(_DATA_DEADLINE, on_timeout=list)
def search_documents(query: str, top: int = 3) -> list[dict[str, Any]]:
    """Full-text query against the index. Returns [] rather than raising."""
    client = search_client()
    if client is None:
        return []
    try:
        results = client.search(search_text=query, top=top)
        return [
            {
                "id": item.get("id", ""),
                "title": item.get("title", ""),
                "content": item.get("content", ""),
                "fund": item.get("fund", ""),
            }
            for item in results
        ]
    except Exception:
        return []


# --- conversation store -------------------------------------------------------


def cosmos_container():
    """Container client for the conversation store, or None when unconfigured."""
    if not COSMOS_ENDPOINT:
        return None
    try:
        # This constructor reaches the account rather than only recording where
        # it is, so it belongs outside the lock more than any other here.
        client = _shared(
            "cosmos",
            lambda: CosmosClient(
                url=COSMOS_ENDPOINT,
                credential=get_credential(),
                connection_timeout=_CONNECT_TIMEOUT,
                retry_total=0,
            ),
        )
        database = client.get_database_client(COSMOS_DATABASE)
        return database.get_container_client(COSMOS_CONTAINER)
    except Exception:
        return None


@_bounded(_DATA_DEADLINE, on_timeout=False)
def save_turn(item: dict[str, Any]) -> bool:
    """Write one explanation to the store. Returns whether it landed."""
    container = cosmos_container()
    if container is None:
        return False
    try:
        container.create_item(body=item)
        return True
    except Exception:
        return False


@_bounded(_DATA_DEADLINE, on_timeout=list)
def read_session(session_id: str, limit: int = 50) -> list[dict[str, Any]]:
    """Every turn for one session, oldest first. Partitioned on sessionId, so
    this is a single-partition query rather than a cross-partition scan."""
    container = cosmos_container()
    if container is None:
        return []
    try:
        items = container.query_items(
            query=(
                "SELECT c.id, c.sessionId, c.question, c.answer, c.createdAt, "
                "c.citations, c.mode FROM c WHERE c.sessionId = @sessionId "
                "ORDER BY c.createdAt ASC"
            ),
            parameters=[{"name": "@sessionId", "value": session_id}],
            partition_key=session_id,
            max_item_count=limit,
        )
        return list(items)
    except Exception:
        return []


# --- documentation corpus -----------------------------------------------------


def blob_service() -> BlobServiceClient | None:
    """Blob client for the documentation account, or None when unconfigured."""
    if not _DOCS_BLOB_ENDPOINT:
        return None
    try:
        return _shared(
            "blob",
            lambda: BlobServiceClient(
                account_url=_DOCS_BLOB_ENDPOINT,
                credential=get_credential(),
                connection_timeout=_CONNECT_TIMEOUT,
                read_timeout=_READ_TIMEOUT,
                retry_total=0,
            ),
        )
    except Exception:
        return None


@_bounded(30, on_timeout=list)
def read_corpus() -> list[dict[str, str]]:
    """Every document in the container, as {name, text}. Empty on any failure."""
    service = blob_service()
    if service is None:
        return []
    try:
        container = service.get_container_client(DOCS_CONTAINER)
        corpus = []
        for blob in container.list_blobs():
            if not blob.name.endswith(".md"):
                continue
            downloader = container.download_blob(blob.name)
            corpus.append(
                {
                    "name": blob.name,
                    "text": downloader.readall().decode("utf-8", errors="replace"),
                }
            )
        return corpus
    except Exception:
        return []


# --- probes for /health and /admin/azure-check --------------------------------


@_bounded(waits_on=_host(IDENTITY_ENDPOINT) or "the platform token endpoint")
def probe_identity() -> dict[str, Any]:
    """Does the platform actually hand this replica a token?"""
    try:
        token = get_credential().get_token(_COGNITIVE_SERVICES_SCOPE)
        return {"ok": bool(token.token), "detail": "token acquired"}
    except Exception as exc:
        return {"ok": False, "detail": _failed(exc)}


@_bounded(waits_on=_host(OPENAI_ENDPOINT))
def probe_openai() -> dict[str, Any]:
    """Control-plane-ish ping: list what the account has deployed.

    Not an inference call: this has to answer on a subscription with no token
    quota, and it has to answer while the app is in stub mode.
    """
    client = openai_client()
    if client is None:
        return {"ok": False, "detail": "no model endpoint configured"}
    try:
        models = client.models.list()
        names = [m.id for m in models]
        return {
            "ok": True,
            "detail": f"{len(names)} deployment(s) visible",
            "endpoint": OPENAI_ENDPOINT,
            "deployment": OPENAI_DEPLOYMENT,
            "api_version": OPENAI_API_VERSION,
        }
    except Exception as exc:
        return {
            "ok": False,
            "detail": _failed(exc),
            "endpoint": OPENAI_ENDPOINT,
            "deployment": OPENAI_DEPLOYMENT,
        }


@_bounded(waits_on=_host(SEARCH_ENDPOINT))
def probe_search() -> dict[str, Any]:
    client = search_client()
    if client is None:
        return {"ok": False, "detail": "no search endpoint configured"}
    try:
        count = client.get_document_count()
        return {
            "ok": True,
            "detail": f"index {SEARCH_INDEX} holds {count} document(s)",
            "endpoint": SEARCH_ENDPOINT,
            "index": SEARCH_INDEX,
            "documents": count,
        }
    except ResourceNotFoundError:
        return {
            "ok": False,
            "detail": f"index {SEARCH_INDEX} does not exist yet",
            "endpoint": SEARCH_ENDPOINT,
            "index": SEARCH_INDEX,
        }
    except Exception as exc:
        return {
            "ok": False,
            "detail": _failed(exc),
            "endpoint": SEARCH_ENDPOINT,
            "index": SEARCH_INDEX,
        }


@_bounded(waits_on=_host(COSMOS_ENDPOINT))
def probe_cosmos() -> dict[str, Any]:
    container = cosmos_container()
    if container is None:
        return {"ok": False, "detail": "no conversation store configured"}
    try:
        container.read()
        return {
            "ok": True,
            "detail": f"container {COSMOS_CONTAINER} reachable",
            "endpoint": COSMOS_ENDPOINT,
            "database": COSMOS_DATABASE,
            "container": COSMOS_CONTAINER,
        }
    except Exception as exc:
        return {
            "ok": False,
            "detail": _failed(exc),
            "endpoint": COSMOS_ENDPOINT,
            "container": COSMOS_CONTAINER,
        }


@_bounded(waits_on=_host(_DOCS_BLOB_ENDPOINT))
def probe_blob() -> dict[str, Any]:
    service = blob_service()
    if service is None:
        return {"ok": False, "detail": "no blob endpoint configured"}
    try:
        container = service.get_container_client(DOCS_CONTAINER)
        properties = container.get_container_properties()
        return {
            "ok": True,
            "detail": f"container {properties.name} reachable",
            "account": DOCS_ACCOUNT,
            "container": DOCS_CONTAINER,
        }
    except Exception as exc:
        return {
            "ok": False,
            "detail": _failed(exc),
            "account": DOCS_ACCOUNT,
            "container": DOCS_CONTAINER,
        }


@_bounded()
def probe_telemetry() -> dict[str, Any]:
    configured = bool(os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"))
    return {
        "ok": configured,
        "detail": "connection string present" if configured else "not configured",
    }
