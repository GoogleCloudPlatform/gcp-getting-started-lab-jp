"""sta-tasks-api on Cloud Run functions (2nd gen) — migrated from Lambda.

Same routes and response shapes as the AWS handler; storage swapped to
Firestore via gcp_clients. Entry point: handler (functions-framework).
"""

import json
import re
import uuid
from datetime import datetime, timezone

import functions_framework

from gcp_clients import bucket_name, gcs, identity_ping, project_id, tasks_collection

JSON_HEADERS = {"content-type": "application/json"}


def _resp(status, body):
    return (json.dumps(body), status, JSON_HEADERS)


def _now():
    return datetime.now(timezone.utc).isoformat()


def create_task(body):
    task = {
        "id": str(uuid.uuid4()),
        "title": body.get("title") or "untitled",
        "due_at": body.get("due_at") or "",
        "status": "open",
        "created_at": _now(),
    }
    tasks_collection().document(task["id"]).set(task)
    return _resp(201, task)


def list_tasks():
    docs = [d.to_dict() for d in tasks_collection().limit(50).stream()]
    docs.sort(key=lambda t: t.get("created_at", ""), reverse=True)
    return _resp(200, {"tasks": docs, "count": len(docs)})


def get_task(task_id):
    snap = tasks_collection().document(task_id).get()
    if not snap.exists:
        return _resp(404, {"error": "not found"})
    return _resp(200, snap.to_dict())


def complete_task(task_id):
    ref = tasks_collection().document(task_id)
    snap = ref.get()
    if not snap.exists:
        return _resp(404, {"error": "not found"})
    ref.update({"status": "done", "completed_at": _now()})
    item = snap.to_dict()
    item.update({"status": "done", "completed_at": _now()})
    return _resp(200, item)


def _ping_firestore():
    list(tasks_collection().limit(1).stream())
    return "ok"


def _ping_gcs():
    # objects.list works with a bucket-scoped objectAdmin grant, unlike
    # bucket.exists() which would need the wider storage.buckets.get.
    list(gcs().list_blobs(bucket_name(), max_results=1))
    return "ok"


def health():
    checks = {}
    for name, fn in (("dynamodb", _ping_firestore), ("s3", _ping_gcs)):
        # keys keep their AWS names so the unmodified smoke test passes
        try:
            checks[name] = fn()
        except Exception as exc:  # noqa: BLE001
            checks[name] = f"fail: {type(exc).__name__}"
    ok = all(v == "ok" for v in checks.values())
    return _resp(200 if ok else 503, {"status": "ok" if ok else "degraded", "checks": checks})


def aws_check():
    checks = {}
    for name, fn in (("dynamodb", _ping_firestore), ("s3", _ping_gcs)):
        try:
            checks[name] = fn()
        except Exception as exc:  # noqa: BLE001
            checks[name] = f"fail: {type(exc).__name__}"
    try:
        identity_ping()
        checks["sts"] = "ok"
        acct = project_id()
    except Exception as exc:  # noqa: BLE001
        checks["sts"] = f"fail: {type(exc).__name__}"
        acct = ""
    overall = "ok" if all(v == "ok" for v in checks.values()) else "fail"
    return _resp(200 if overall == "ok" else 503,
                 {"overall": overall, "checks": checks, "account_suffix": str(acct)[-4:]})


ROUTES = [
    ("POST", re.compile(r"^/tasks$"), lambda m, b: create_task(b)),
    ("GET", re.compile(r"^/tasks$"), lambda m, b: list_tasks()),
    ("GET", re.compile(r"^/tasks/(?P<id>[0-9a-f-]+)$"), lambda m, b: get_task(m.group("id"))),
    ("POST", re.compile(r"^/tasks/(?P<id>[0-9a-f-]+)/complete$"), lambda m, b: complete_task(m.group("id"))),
    ("GET", re.compile(r"^/health$"), lambda m, b: health()),
    ("GET", re.compile(r"^/admin/aws-check$"), lambda m, b: aws_check()),
]


@functions_framework.http
def handler(request):
    method = request.method
    path = request.path or "/"
    body = request.get_json(silent=True) or {}
    for verb, pattern, fn in ROUTES:
        if verb == method:
            m = pattern.match(path)
            if m:
                try:
                    return fn(m, body)
                except Exception as exc:  # noqa: BLE001
                    return _resp(500, {"error": type(exc).__name__})
    return _resp(404, {"error": f"no route for {method} {path}"})
