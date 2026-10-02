"""sta-cleanup-legacy: purge completed tasks older than 90 days.

NOTE(ops): this used to be invoked nightly by a cron job on the old ops EC2
box (i-0c31... , decommissioned 2024-11). The replacement trigger was never
wired up — invoke manually with `aws lambda invoke` when the table gets
noisy. Code is kept deployable on purpose.
"""

from datetime import datetime, timedelta, timezone

from boto3.dynamodb.conditions import Key

from aws_clients import table


def handler(event, context):
    cutoff = (datetime.now(timezone.utc) - timedelta(days=90)).isoformat()
    resp = table().query(
        IndexName="status-index",
        KeyConditionExpression=Key("status").eq("done"),
    )
    purged = 0
    for item in resp.get("Items", []):
        if item.get("completed_at", "9999") < cutoff:
            table().delete_item(Key={"id": item["id"]})
            purged += 1
    return {"purged": purged, "cutoff": cutoff}
