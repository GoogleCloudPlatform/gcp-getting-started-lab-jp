"""sta-export-worker on Cloud Run functions — invoked by Cloud Scheduler (OIDC).

Full-collection snapshot to gs://<bucket>/exports/YYYY-MM-DD.json,
mirroring the Lambda + EventBridge original.
"""

import json
from datetime import datetime, timezone

import functions_framework

from gcp_clients import bucket_name, gcs, tasks_collection


@functions_framework.http
def handler(request):
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    items = [d.to_dict() for d in tasks_collection().stream()]
    key = f"exports/{today}.json"
    gcs().bucket(bucket_name()).blob(key).upload_from_string(
        json.dumps({"exported_at": datetime.now(timezone.utc).isoformat(),
                    "count": len(items), "tasks": items}, default=str),
        content_type="application/json",
    )
    return (json.dumps({"exported": len(items), "key": key}), 200,
            {"content-type": "application/json"})
