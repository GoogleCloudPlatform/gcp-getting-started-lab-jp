"""app.py — Online shop web store (Flask + gunicorn :8000).

The whole shop: catalog list/detail pages rendered from PostgreSQL, cover
images streamed from the private assets bucket, and the two operational
endpoints every service here exposes:

    GET /health           dependency substatus JSON — never raises
    GET /admin/aws-check  per-service SDK ping dashboard

Every AWS SDK call goes through aws_clients.py (the funnel); this module
never imports boto3 directly.
"""

import os
import threading
import time

from flask import Flask, Response, abort, jsonify, redirect, render_template, url_for

import aws_clients as cloud
import db

app = Flask(__name__)


def _try(fn):
    """ok / 'fail: <ExceptionName>' — shared by /health and /admin/aws-check."""
    try:
        fn()
        return "ok"
    except Exception as exc:  # noqa: BLE001 — status endpoints never raise
        return f"fail: {type(exc).__name__}"


# ---- storefront ---------------------------------------------------------------

@app.get("/")
def index():
    return redirect(url_for("book_list"))


@app.get("/books")
def book_list():
    books = db.list_books()
    return render_template("book_list.html", books=books)


@app.get("/books/<int:book_id>")
def book_detail(book_id):
    book = db.get_book(book_id)
    if book is None:
        abort(404)
    return render_template("book_detail.html", book=book)


@app.get("/covers/<path:key>")
def cover(key):
    # Covers live under covers/<id>.png in the assets bucket; anything else
    # (slashes, other extensions) is a 404, not an S3 round-trip.
    if "/" in key or not key.endswith(".png"):
        abort(404)
    try:
        body, content_type = cloud.get_asset(f"covers/{key}")
    except Exception:  # noqa: BLE001 — missing object or S3 hiccup -> plain 404
        abort(404)
    return Response(
        body,
        mimetype=content_type or "image/png",
        headers={"Cache-Control": "public, max-age=3600"},
    )


# ---- operations ------------------------------------------------------------------

@app.get("/health")
def health():
    """Dependency substatus. Always answers 200 with a JSON body; the load
    balancer treats a connect failure (gunicorn down) as unhealthy, not a
    degraded dependency — that behaviour dates back to the 2016 build."""
    checks = {
        "database": _try(db.ping),
        "s3": _try(cloud.bucket_ok),
    }
    status = "ok" if all(v == "ok" for v in checks.values()) else "degraded"
    return jsonify({"status": status, "checks": checks})


@app.get("/admin/aws-check")
def aws_check():
    """Per-service SDK ping — the parity dashboard. One line per dependency:
    S3 list, both secret describes, DB version, CloudWatch metric push, STS
    caller identity."""
    secret_db = os.environ.get("SECRET_ID_DB", "ttw-db-password")
    secret_legacy = os.environ.get("SECRET_ID_LEGACY", "ttw-legacy-api-key")
    results = {
        "s3": _try(cloud.list_one),
        "secret_db": _try(lambda: cloud.secret_status(secret_db)),
        "secret_legacy": _try(lambda: cloud.secret_status(secret_legacy)),
        "database": _try(db.server_version),
        "cloudwatch": _try(cloud.put_health_ping),
        "sts": _try(cloud.whoami),
    }
    identity = None
    if results["sts"] == "ok":
        try:
            identity = cloud.whoami()
        except Exception:  # noqa: BLE001
            identity = None
    return jsonify({**results, "identity": identity})


# ---- startup convergence -----------------------------------------------------------

def _bootstrap_async():
    """Create schema + seed as soon as the database accepts connections.

    A fresh ASG instance often comes up before RDS finishes its own boot (or
    before Secrets Manager is reachable through a cold network path), so
    retry quietly in the background; /health reports the database substatus
    honestly in the meantime.
    """
    for _ in range(60):
        try:
            db.bootstrap()
            return
        except Exception:  # noqa: BLE001
            time.sleep(5)


threading.Thread(target=_bootstrap_async, daemon=True).start()


if __name__ == "__main__":
    # Local convenience only; production runs `gunicorn app:app` via systemd.
    app.run(host="0.0.0.0", port=8000, debug=False)
