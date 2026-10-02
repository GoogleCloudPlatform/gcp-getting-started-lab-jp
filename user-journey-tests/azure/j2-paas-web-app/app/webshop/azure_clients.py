"""azure_clients.py — the single funnel for EVERY Azure SDK call the storefront makes.

Keep any new Azure call in this module so call sites stay grep-able.

Intended GCP mapping (planning notes, per service):
  Blob container `media` on pwamedia<uniq>  -> Cloud Storage bucket, same object keys
  Key Vault pwa-kv-<uniq> secrets           -> Secret Manager, one secret per key
  System-assigned managed identity          -> Workload Identity + a service account
  Application Insights connection string    -> Cloud Trace / Cloud Monitoring via OpenTelemetry
  PostgreSQL flexible server pwa-pg-<uniq>  -> Cloud SQL for PostgreSQL

Credentials: none are configured here. On App Service the site's system-assigned
identity is what DefaultAzureCredential picks up, from the IDENTITY_ENDPOINT and
IDENTITY_HEADER pair the platform injects into the worker. Running the same code
on a laptop, the same class falls back to whoever is signed in to the Azure CLI.

Nothing in this module raises on a service being unreachable. Every entry point
returns a (ok, detail) shape or a safe default, because /health and
/admin/azure-check have to answer even when a dependency is down.
"""

from __future__ import annotations

import os
import threading
from typing import Any

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobServiceClient

MEDIA_ACCOUNT = os.environ.get("PWA_MEDIA_ACCOUNT", "")
MEDIA_CONTAINER = os.environ.get("PWA_MEDIA_CONTAINER", "media")
KEY_VAULT_URI = os.environ.get("PWA_KEY_VAULT_URI", "")
CHECKOUT_SECRET_NAME = os.environ.get(
    "PWA_CHECKOUT_SECRET_NAME", "checkout-webhook-signing-key"
)

_BLOB_ENDPOINT = os.environ.get("PWA_MEDIA_BLOB_ENDPOINT") or (
    f"https://{MEDIA_ACCOUNT}.blob.core.windows.net/" if MEDIA_ACCOUNT else ""
)

# Every SDK client and the credential are built with a bounded budget. The
# storefront calls these from inside a request and from worker startup, and the
# SDK's own default is to retry an unreachable endpoint for minutes — longer
# than the gunicorn worker timeout, which turns one sick dependency into a dead
# worker. A dependency that cannot answer in this budget counts as down.
_SDK_BUDGET: dict[str, Any] = {
    "connection_timeout": 5,
    "read_timeout": 10,
    "retry_total": 1,
}

# Reentrant: get_blob_service() and get_secret_client() both build their client
# with get_credential(), which takes this same lock. A plain Lock deadlocks the
# calling thread against itself the first time either one is used.
_lock = threading.RLock()
_credential: DefaultAzureCredential | None = None
_blob_service: BlobServiceClient | None = None
_secret_client: SecretClient | None = None

# Filled in once at startup by storefront.apps.StorefrontConfig.ready().
_checkout_signing_key: str = ""


def get_credential() -> DefaultAzureCredential:
    """One credential for the whole process; the SDK caches tokens behind it."""
    global _credential
    with _lock:
        if _credential is None:
            # process_timeout bounds the credentials that shell out to a CLI.
            _credential = DefaultAzureCredential(process_timeout=5, **_SDK_BUDGET)
        return _credential


def get_blob_service() -> BlobServiceClient | None:
    """Blob client for the product image account, or None when unconfigured."""
    global _blob_service
    if not _BLOB_ENDPOINT:
        return None
    with _lock:
        if _blob_service is None:
            _blob_service = BlobServiceClient(
                account_url=_BLOB_ENDPOINT, credential=get_credential(), **_SDK_BUDGET
            )
        return _blob_service


def get_secret_client() -> SecretClient | None:
    """Key Vault client, or None when no vault is configured."""
    global _secret_client
    if not KEY_VAULT_URI:
        return None
    with _lock:
        if _secret_client is None:
            _secret_client = SecretClient(
                vault_url=KEY_VAULT_URI, credential=get_credential(), **_SDK_BUDGET
            )
        return _secret_client


# --- product images ---------------------------------------------------------


def media_url(blob_name: str) -> str:
    """Public path the storefront links to. The container itself stays private,
    so images are served back through the app rather than straight off blob."""
    if not blob_name:
        return ""
    return f"/media/{blob_name}"


def download_media(blob_name: str) -> tuple[bytes, str] | None:
    """Fetch one product image. Returns (content, content_type) or None."""
    service = get_blob_service()
    if service is None:
        return None
    try:
        blob = service.get_blob_client(container=MEDIA_CONTAINER, blob=blob_name)
        stream = blob.download_blob()
        content = stream.readall()
        settings = getattr(stream, "properties", None)
        content_type = "application/octet-stream"
        if settings is not None and settings.content_settings.content_type:
            content_type = settings.content_settings.content_type
        return content, content_type
    except Exception:
        return None


def list_media(limit: int = 5) -> list[str]:
    """Names of the first few product images, used by the parity dashboard."""
    service = get_blob_service()
    if service is None:
        return []
    try:
        container = service.get_container_client(MEDIA_CONTAINER)
        names = []
        for blob in container.list_blobs():
            names.append(blob.name)
            if len(names) >= limit:
                break
        return names
    except Exception:
        return []


# --- secrets ----------------------------------------------------------------


def read_checkout_signing_key() -> str:
    """Read the checkout webhook signing key from the vault.

    App Service also injects the same value as PWA_CHECKOUT_SIGNING_KEY through a
    vault reference on the app setting. The direct read is what runs first; the
    app setting is the fallback for anywhere the identity cannot reach the vault.
    """
    client = get_secret_client()
    if client is not None:
        try:
            secret = client.get_secret(CHECKOUT_SECRET_NAME)
            if secret.value:
                return secret.value
        except Exception:
            pass

    # When the platform cannot resolve a vault reference it hands the worker the
    # reference text instead of the secret. That is an absent key, not a key
    # whose value happens to start with an @, and signing anything with it would
    # be worse than refusing to sign.
    fallback = os.environ.get("PWA_CHECKOUT_SIGNING_KEY", "")
    if fallback.startswith("@Microsoft.KeyVault("):
        return ""
    return fallback


def load_checkout_signing_key() -> str:
    """Called once at startup. Never raises."""
    global _checkout_signing_key
    _checkout_signing_key = read_checkout_signing_key()
    return _checkout_signing_key


def checkout_signing_key() -> str:
    return _checkout_signing_key


# --- probes for /health and /admin/azure-check ------------------------------


def probe_blob() -> dict[str, Any]:
    service = get_blob_service()
    if service is None:
        return {"ok": False, "detail": "no blob endpoint configured"}
    try:
        container = service.get_container_client(MEDIA_CONTAINER)
        properties = container.get_container_properties()
        return {
            "ok": True,
            "detail": f"container {properties.name} reachable",
            "account": MEDIA_ACCOUNT,
            "container": MEDIA_CONTAINER,
        }
    except Exception as exc:
        return {
            "ok": False,
            "detail": f"{type(exc).__name__}",
            "account": MEDIA_ACCOUNT,
            "container": MEDIA_CONTAINER,
        }


def probe_vault() -> dict[str, Any]:
    client = get_secret_client()
    if client is None:
        return {"ok": False, "detail": "no vault configured"}
    try:
        secret = client.get_secret(CHECKOUT_SECRET_NAME)
        return {
            "ok": True,
            "detail": f"secret {CHECKOUT_SECRET_NAME} readable",
            "vault": KEY_VAULT_URI,
            "value_length": len(secret.value or ""),
        }
    except Exception as exc:
        return {
            "ok": False,
            "detail": f"{type(exc).__name__}",
            "vault": KEY_VAULT_URI,
        }


def probe_identity() -> dict[str, Any]:
    """Does the platform actually hand this worker a token?"""
    try:
        token = get_credential().get_token("https://management.azure.com/.default")
        return {"ok": bool(token.token), "detail": "token acquired"}
    except Exception as exc:
        return {"ok": False, "detail": f"{type(exc).__name__}"}


def probe_telemetry() -> dict[str, Any]:
    configured = bool(os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"))
    return {
        "ok": configured,
        "detail": "connection string present" if configured else "not configured",
    }
