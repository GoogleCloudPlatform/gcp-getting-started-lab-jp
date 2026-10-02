#!/usr/bin/env bash
# 04-bucket.sh — transcript bucket + lifecycle + SA grant (idempotent).
#
# Mirrors the AWS side: private bucket, 90-day expiry under transcripts/.
# Google-managed encryption at rest is the default (the SSE-S3 analogue).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if gcloud storage buckets describe "gs://${BUCKET_NAME}" \
    --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo ">>> Bucket gs://${BUCKET_NAME} already exists"
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --location "${GCP_REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --project "${GCP_PROJECT}"
  echo ">>> Created gs://${BUCKET_NAME}"
fi

# Lifecycle: expire transcript objects after 90 days (parity with S3 rule).
LIFECYCLE_FILE="$(mktemp)"
trap 'rm -f "$LIFECYCLE_FILE"' EXIT
cat > "$LIFECYCLE_FILE" <<'JSON'
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 90, "matchesPrefix": ["transcripts/"]}
    }
  ]
}
JSON
gcloud storage buckets update "gs://${BUCKET_NAME}" \
  --lifecycle-file="$LIFECYCLE_FILE" \
  --project "${GCP_PROJECT}"
echo ">>> Lifecycle set (expire transcripts/ after 90 days)"

# Bucket-scoped object access for the runtime SA (add is a no-op if present).
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/storage.objectAdmin \
  --project "${GCP_PROJECT}" >/dev/null
echo ">>> Granted roles/storage.objectAdmin on the bucket to ${SA_EMAIL}"
