"""azure_clients.py — the single funnel for EVERY Azure call the portal makes.

Keep any new Azure call in this module so call sites stay grep-able.

Intended GCP mapping (planning notes, per service):
  Blob container `documents` on cpiportal<uniq>  -> Cloud Storage bucket, same object keys
  SQL Database cpiportal (Basic, 5 DTU)          -> Cloud SQL for SQL Server, smallest shared-core
  Storage account key in an app setting          -> Secret Manager secret read at startup
  SQL login + password in a connection string    -> Secret Manager, or IAM database authentication
  App Service B1 Linux plan                      -> Cloud Run service, min instances 1

Credentials: the portal has no identity of its own. App Service hands the worker
two secrets through configuration and both are read here and nowhere else --
`AZURE_STORAGE_CONNECTION_STRING` for the document library, and the site's
`PortalDb` connection string entry, which the platform exposes to the process as
`SQLAZURECONNSTR_PortalDb`. Nothing in this module ever logs either value.

Nothing here raises on a service being unreachable. Every entry point returns a
(ok, detail) shape or a safe default, because /health and /admin/azure-check
have to answer even when a dependency is down.
"""

from __future__ import annotations

import os
import threading
from typing import Any

import pymssql
from azure.storage.blob import BlobServiceClient

DOCUMENTS_CONTAINER = os.environ.get("CPI_DOCUMENTS_CONTAINER", "documents")
STORAGE_ACCOUNT = os.environ.get("CPI_STORAGE_ACCOUNT", "")
STORAGE_CONNECTION_STRING = os.environ.get("AZURE_STORAGE_CONNECTION_STRING", "")

# App Service prefixes every connection string entry with its type. The entry is
# named PortalDb and typed SQLAzure, so the worker sees SQLAZURECONNSTR_PortalDb.
SQL_CONNECTION_STRING = os.environ.get("SQLAZURECONNSTR_PortalDb", "")

# A student opening the notice board should get an error page in a couple of
# seconds when the database is unreachable, not a worker parked on a TCP connect.
SQL_LOGIN_TIMEOUT_SECONDS = 5
SQL_QUERY_TIMEOUT_SECONDS = 15

# The same reasoning applies to storage, and here it has teeth: the site runs one
# worker, so a request waiting on blob blocks the notice board too, and the
# platform's health probe gives up after a minute. Left at its defaults the SDK
# retries three times with an exponential backoff and takes well over that.
BLOB_CONNECT_TIMEOUT_SECONDS = 5
BLOB_READ_TIMEOUT_SECONDS = 15
BLOB_RETRY_TOTAL = 1

_lock = threading.Lock()
_blob_service: BlobServiceClient | None = None

# ADO.NET spells the same four fields several ways depending on which blade or
# tool wrote the string. Accept all of them and normalise.
_ADO_FIELD_ALIASES = {
    "server": "server",
    "data source": "server",
    "address": "server",
    "addr": "server",
    "network address": "server",
    "initial catalog": "database",
    "database": "database",
    "user id": "user",
    "uid": "user",
    "user": "user",
    "password": "password",
    "pwd": "password",
}


def _split_ado_pairs(raw: str) -> dict[str, str]:
    """Read an ADO.NET connection string into its key/value pairs.

    Splitting on ";" is not enough. A value containing a semicolon — a password
    rotated by hand in the portal, most likely — is written quoted, and a quote
    inside a quoted value is written twice. Both forms have to survive, because
    getting them wrong yields a settings dict that looks complete and fails at
    the login with nothing to point at.
    """
    fields: dict[str, str] = {}
    index, length = 0, len(raw)
    while index < length:
        equals = raw.find("=", index)
        if equals == -1:
            break
        key = raw[index:equals].strip().lower()
        index = equals + 1
        while index < length and raw[index] == " ":
            index += 1

        if index < length and raw[index] in "'\"":
            quote = raw[index]
            index += 1
            chars: list[str] = []
            while index < length:
                if raw[index] == quote:
                    if index + 1 < length and raw[index + 1] == quote:
                        chars.append(quote)
                        index += 2
                        continue
                    index += 1
                    break
                chars.append(raw[index])
                index += 1
            value = "".join(chars)
            semicolon = raw.find(";", index)
            index = length if semicolon == -1 else semicolon + 1
        else:
            semicolon = raw.find(";", index)
            end = length if semicolon == -1 else semicolon
            value = raw[index:end].strip()
            index = end + 1

        if key:
            fields[key] = value
    return fields


def parse_sql_connection_string(raw: str) -> dict[str, Any]:
    """Split an ADO.NET connection string into pymssql keyword arguments.

    Returns an empty dict when the string is missing or carries no server, so
    callers can treat "not configured" and "unparseable" the same way.
    """
    fields: dict[str, str] = {}
    for key, value in _split_ado_pairs(raw).items():
        field = _ADO_FIELD_ALIASES.get(key)
        if field:
            fields[field] = value

    server = fields.get("server", "")
    if server.lower().startswith("tcp:"):
        server = server[4:]
    port = 1433
    if "," in server:
        server, _, port_text = server.partition(",")
        if port_text.strip().isdigit():
            port = int(port_text.strip())
    if not server:
        return {}

    return {
        "server": server,
        "port": port,
        "user": fields.get("user", ""),
        "password": fields.get("password", ""),
        "database": fields.get("database", ""),
        "login_timeout": SQL_LOGIN_TIMEOUT_SECONDS,
        "timeout": SQL_QUERY_TIMEOUT_SECONDS,
    }


def sql_target() -> str:
    """Server and database the portal is pointed at, safe to show on a page."""
    settings = parse_sql_connection_string(SQL_CONNECTION_STRING)
    if not settings:
        return ""
    return f"{settings['server']}/{settings['database']}"


def get_blob_service() -> BlobServiceClient | None:
    """Blob client for the document library, or None when it cannot be built.

    A malformed connection string raises out of the SDK constructor, so the
    construction is guarded here rather than at each call site — every caller is
    already written to handle None, and none of them may raise.
    """
    global _blob_service
    if not STORAGE_CONNECTION_STRING:
        return None
    with _lock:
        if _blob_service is None:
            try:
                _blob_service = BlobServiceClient.from_connection_string(
                    STORAGE_CONNECTION_STRING,
                    connection_timeout=BLOB_CONNECT_TIMEOUT_SECONDS,
                    read_timeout=BLOB_READ_TIMEOUT_SECONDS,
                    retry_total=BLOB_RETRY_TOTAL,
                )
            except Exception:
                return None
        return _blob_service


def sql_connect():
    """Open a connection to the notice board database, or return None.

    A fresh connection per request. The Basic service objective allows far more
    concurrent sessions than a single-worker site can open, and pooling would
    only hide a dead connection until the next student hit it.
    """
    settings = parse_sql_connection_string(SQL_CONNECTION_STRING)
    if not settings:
        return None
    try:
        return pymssql.connect(**settings)
    except Exception:
        return None


# --- notices ----------------------------------------------------------------


def fetch_notices(limit: int = 20) -> list[dict[str, Any]]:
    """Most recent notices first. Returns [] when the board is unreachable."""
    connection = sql_connect()
    if connection is None:
        return []
    try:
        with connection:
            cursor = connection.cursor(as_dict=True)
            cursor.execute(
                "SELECT TOP (%d) id, posted_on, category, title, body"
                " FROM dbo.notices ORDER BY posted_on DESC, id DESC",
                limit,
            )
            return [_notice_row(row) for row in cursor.fetchall()]
    except Exception:
        return []


def fetch_notice(notice_id: int) -> dict[str, Any] | None:
    """One notice by id, or None when it is missing or the board is down."""
    connection = sql_connect()
    if connection is None:
        return None
    try:
        with connection:
            cursor = connection.cursor(as_dict=True)
            cursor.execute(
                "SELECT id, posted_on, category, title, body"
                " FROM dbo.notices WHERE id = %d",
                notice_id,
            )
            row = cursor.fetchone()
            return _notice_row(row) if row else None
    except Exception:
        return None


def _notice_row(row: dict[str, Any]) -> dict[str, Any]:
    posted_on = row.get("posted_on")
    return {
        "id": row.get("id"),
        "posted_on": posted_on.isoformat() if posted_on is not None else "",
        "category": row.get("category") or "",
        "title": row.get("title") or "",
        "body": row.get("body") or "",
    }


# --- document library -------------------------------------------------------


def list_documents(limit: int = 50) -> list[dict[str, Any]]:
    """Everything the registrar has published. Returns [] when unreachable."""
    service = get_blob_service()
    if service is None:
        return []
    try:
        container = service.get_container_client(DOCUMENTS_CONTAINER)
        documents = []
        for blob in container.list_blobs():
            last_modified = getattr(blob, "last_modified", None)
            documents.append(
                {
                    "name": blob.name,
                    "size": blob.size or 0,
                    "last_modified": (
                        last_modified.isoformat() if last_modified else ""
                    ),
                }
            )
            if len(documents) >= limit:
                break
        return sorted(documents, key=lambda document: document["name"])
    except Exception:
        return []


def download_document(name: str) -> tuple[bytes, str] | None:
    """Fetch one published document. Returns (content, content_type) or None.

    The container is private, so documents are served back through the site
    rather than linked to directly.
    """
    if not name:
        return None
    service = get_blob_service()
    if service is None:
        return None
    try:
        blob = service.get_blob_client(container=DOCUMENTS_CONTAINER, blob=name)
        stream = blob.download_blob()
        content = stream.readall()
        content_type = "application/octet-stream"
        properties = getattr(stream, "properties", None)
        if properties is not None and properties.content_settings.content_type:
            content_type = properties.content_settings.content_type
        return content, content_type
    except Exception:
        return None


# --- probes for /health and /admin/azure-check ------------------------------


def probe_sql() -> dict[str, Any]:
    if not parse_sql_connection_string(SQL_CONNECTION_STRING):
        return {"ok": False, "detail": "no database connection string configured"}
    connection = sql_connect()
    if connection is None:
        return {"ok": False, "detail": "connection refused", "target": sql_target()}
    try:
        with connection:
            cursor = connection.cursor()
            cursor.execute("SELECT COUNT(*) FROM dbo.notices")
            (count,) = cursor.fetchone()
        return {
            "ok": True,
            "detail": f"{count} notices on the board",
            "target": sql_target(),
            "notice_count": count,
        }
    except Exception as exc:
        return {
            "ok": False,
            "detail": type(exc).__name__,
            "target": sql_target(),
        }


def probe_blob() -> dict[str, Any]:
    service = get_blob_service()
    if service is None:
        detail = (
            "storage connection string could not be read"
            if STORAGE_CONNECTION_STRING
            else "no storage connection string configured"
        )
        return {"ok": False, "detail": detail}
    try:
        container = service.get_container_client(DOCUMENTS_CONTAINER)
        properties = container.get_container_properties()
        return {
            "ok": True,
            "detail": f"container {properties.name} reachable",
            "account": STORAGE_ACCOUNT,
            "container": DOCUMENTS_CONTAINER,
        }
    except Exception as exc:
        return {
            "ok": False,
            "detail": type(exc).__name__,
            "account": STORAGE_ACCOUNT,
            "container": DOCUMENTS_CONTAINER,
        }
