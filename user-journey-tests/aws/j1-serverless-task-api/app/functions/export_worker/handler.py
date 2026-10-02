"""sta-export-worker: nightly EventBridge schedule (cron 00:00 UTC).

Scans the whole task table and drops a dated JSON snapshot into the exports
bucket under exports/YYYY-MM-DD.json. Ops pulls these into the weekly
spreadsheet; nothing downstream is latency-sensitive.
"""

import json
from datetime import datetime, timezone

from aws_clients import bucket_name, s3, table


def _scan_all():
    items, resp = [], table().scan()
    items.extend(resp.get("Items", []))
    while "LastEvaluatedKey" in resp:
        resp = table().scan(ExclusiveStartKey=resp["LastEvaluatedKey"])
        items.extend(resp.get("Items", []))
    return items


def handler(event, context):
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    items = _scan_all()
    key = f"exports/{today}.json"
    s3().put_object(
        Bucket=bucket_name(),
        Key=key,
        Body=json.dumps({"exported_at": datetime.now(timezone.utc).isoformat(),
                         "count": len(items), "tasks": items}, default=str).encode(),
        ContentType="application/json",
    )
    return {"exported": len(items), "key": key}
