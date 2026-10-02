"""HTTP routes for the student portal.

Four pages a student sees, plus the two operational endpoints the IT office
watches. No Azure call is made here — everything goes through azure_clients.
"""

from __future__ import annotations

import os

from flask import Response, abort, jsonify, render_template

from portal import app, azure_clients

UNIVERSITY_NAME = "The University"
NOTICES_ON_FRONT_PAGE = 20


@app.route("/")
def notice_board():
    """The front page: whatever the registrar has posted, newest first."""
    notices = azure_clients.fetch_notices(NOTICES_ON_FRONT_PAGE)
    return render_template(
        "notices.html",
        university=UNIVERSITY_NAME,
        notices=notices,
        board_reachable=bool(notices) or azure_clients.probe_sql()["ok"],
    )


@app.route("/notices/<int:notice_id>")
def notice_detail(notice_id: int):
    """One notice in full."""
    notice = azure_clients.fetch_notice(notice_id)
    if notice is None:
        abort(404)
    return render_template(
        "notice_detail.html", university=UNIVERSITY_NAME, notice=notice
    )


@app.route("/documents")
def document_library():
    """Forms and handbooks the registrar's office publishes."""
    documents = azure_clients.list_documents()
    return render_template(
        "documents.html",
        university=UNIVERSITY_NAME,
        documents=documents,
        library_reachable=bool(documents) or azure_clients.probe_blob()["ok"],
    )


@app.route("/documents/<path:name>")
def document_download(name: str):
    """Serve one document back. The container itself is private."""
    fetched = azure_clients.download_document(name)
    if fetched is None:
        abort(404)
    content, content_type = fetched
    return Response(content, mimetype=content_type)


@app.route("/health")
def health():
    """Dependency check for the platform's health probe.

    Always answers 200. App Service is configured to probe this path, and it
    recycles an instance that answers otherwise -- an empty notice board or a
    database in maintenance is a degraded portal, not a broken worker, and
    restarting the worker would not fix either. The body carries the verdict.
    """
    checks = {
        "notice_board": azure_clients.probe_sql(),
        "document_library": azure_clients.probe_blob(),
    }
    healthy = all(check["ok"] for check in checks.values())
    return jsonify(
        {
            "status": "ok" if healthy else "degraded",
            "service": "cpi-portal",
            "checks": checks,
        }
    )


@app.route("/admin/azure-check")
def azure_check():
    """Parity dashboard: one line per service the portal depends on.

    After the migration the same page reports on the replacements, so the two
    sides can be compared without rewriting the check.
    """
    sql = azure_clients.probe_sql()
    blob = azure_clients.probe_blob()
    services = {
        "sql_database": {
            "ok": sql["ok"],
            "detail": sql["detail"],
            "target": sql.get("target", ""),
            "database": os.environ.get("CPI_SQL_DATABASE", ""),
        },
        "blob_storage": {
            "ok": blob["ok"],
            "detail": blob["detail"],
            "account": blob.get("account", ""),
            "container": blob.get("container", ""),
        },
    }
    return jsonify(
        {
            "provider": "azure",
            "service": "cpi-portal",
            "all_ok": all(service["ok"] for service in services.values()),
            "services": services,
        }
    )
