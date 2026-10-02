"""sta-tasks-api: the task-reminder HTTP API, one Lambda behind API Gateway HTTP API.

Routes (API Gateway v2 proxy payload):
    POST /tasks                  create {title, due_at}
    GET  /tasks                  list (most recent 50)
    GET  /tasks/{id}             fetch one
    POST /tasks/{id}/complete    mark done
    GET  /health                 dependency substatus, always 200-or-503, never raises
    GET  /admin/aws-check        per-service SDK ping dashboard
"""

import json
import re
import uuid
from datetime import datetime, timezone

from aws_clients import bucket_name, s3, sts, table

JSON_HEADERS = {"content-type": "application/json"}


def _resp(status, body):
    return {"statusCode": status, "headers": JSON_HEADERS, "body": json.dumps(body)}


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
    table().put_item(Item=task)
    return _resp(201, task)


def list_tasks():
    items = table().scan(Limit=50).get("Items", [])
    items.sort(key=lambda t: t.get("created_at", ""), reverse=True)
    return _resp(200, {"tasks": items, "count": len(items)})


def get_task(task_id):
    item = table().get_item(Key={"id": task_id}).get("Item")
    if not item:
        return _resp(404, {"error": "not found"})
    return _resp(200, item)


def complete_task(task_id):
    item = table().get_item(Key={"id": task_id}).get("Item")
    if not item:
        return _resp(404, {"error": "not found"})
    table().update_item(
        Key={"id": task_id},
        UpdateExpression="SET #s = :done, completed_at = :ts",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":done": "done", ":ts": _now()},
    )
    item.update({"status": "done", "completed_at": _now()})
    return _resp(200, item)


def health():
    checks = {}
    try:
        table().meta.client.describe_table(TableName=table().name)
        checks["dynamodb"] = "ok"
    except Exception as exc:  # noqa: BLE001 - health must never raise
        checks["dynamodb"] = f"fail: {type(exc).__name__}"
    try:
        s3().head_bucket(Bucket=bucket_name())
        checks["s3"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["s3"] = f"fail: {type(exc).__name__}"
    ok = all(v == "ok" for v in checks.values())
    return _resp(200 if ok else 503, {"status": "ok" if ok else "degraded", "checks": checks})


def aws_check():
    checks = {}
    try:
        table().meta.client.describe_table(TableName=table().name)
        checks["dynamodb"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["dynamodb"] = f"fail: {type(exc).__name__}"
    try:
        s3().head_bucket(Bucket=bucket_name())
        checks["s3"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["s3"] = f"fail: {type(exc).__name__}"
    try:
        ident = sts().get_caller_identity()
        checks["sts"] = "ok"
        account = ident.get("Account", "")
    except Exception as exc:  # noqa: BLE001
        checks["sts"] = f"fail: {type(exc).__name__}"
        account = ""
    overall = "ok" if all(v == "ok" for v in checks.values()) else "fail"
    return _resp(200 if overall == "ok" else 503, {"overall": overall, "checks": checks, "account_suffix": account[-4:]})


ROUTES = [
    ("POST", re.compile(r"^/tasks$"), lambda m, b: create_task(b)),
    ("GET", re.compile(r"^/tasks$"), lambda m, b: list_tasks()),
    ("GET", re.compile(r"^/tasks/(?P<id>[0-9a-f-]+)$"), lambda m, b: get_task(m.group("id"))),
    ("POST", re.compile(r"^/tasks/(?P<id>[0-9a-f-]+)/complete$"), lambda m, b: complete_task(m.group("id"))),
    ("GET", re.compile(r"^/health$"), lambda m, b: health()),
    ("GET", re.compile(r"^/admin/aws-check$"), lambda m, b: aws_check()),
]


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "/")
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _resp(400, {"error": "invalid JSON body"})
    for verb, pattern, fn in ROUTES:
        if verb == method:
            m = pattern.match(path)
            if m:
                try:
                    return fn(m, body)
                except Exception as exc:  # noqa: BLE001 - surface as 500, don't crash the runtime
                    return _resp(500, {"error": type(exc).__name__})
    return _resp(404, {"error": f"no route for {method} {path}"})
