"""sta-cleanup-legacy on Cloud Run functions — deployed with NO scheduler,
mirroring the orphaned Lambda on the AWS side (its cron was never re-attached).
Invoke manually with an authenticated request when needed.
"""

import json
from datetime import datetime, timedelta, timezone

import functions_framework
from google.cloud.firestore_v1.base_query import FieldFilter

from gcp_clients import tasks_collection


@functions_framework.http
def handler(request):
    cutoff = (datetime.now(timezone.utc) - timedelta(days=90)).isoformat()
    purged = 0
    query = tasks_collection().where(filter=FieldFilter("status", "==", "done"))
    for snap in query.stream():
        item = snap.to_dict()
        if item.get("completed_at", "9999") < cutoff:
            snap.reference.delete()
            purged += 1
    return (json.dumps({"purged": purged, "cutoff": cutoff}), 200,
            {"content-type": "application/json"})
