#!/usr/bin/env bash
# 02-functions.sh — deploy the three Cloud Run functions (2nd gen, python312).
# sta-cleanup-legacy is deployed WITHOUT any scheduler on purpose (parity with
# the orphaned Lambda on the AWS side). Idempotent: deploy = create-or-update.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
"$(dirname "$0")/../build.sh"

BUILD="$(cd "$(dirname "$0")/.." && pwd)/build"
COMMON=(--gen2 --runtime=python312 --region="${GCP_REGION}" --project="${GCP_PROJECT}"
        --entry-point=handler --memory=256Mi --timeout=60s
        --set-env-vars="GCP_PROJECT=${GCP_PROJECT},FIRESTORE_DB=${FIRESTORE_DB},BUCKET=${BUCKET}")

# public HTTP API
gcloud functions deploy sta-tasks-api "${COMMON[@]}" \
  --source="${BUILD}/tasks_api" --trigger-http --allow-unauthenticated

# scheduler-invoked worker (auth required)
gcloud functions deploy sta-export-worker "${COMMON[@]}" \
  --source="${BUILD}/export_worker" --trigger-http --no-allow-unauthenticated

# orphan: deployed, never scheduled
gcloud functions deploy sta-cleanup-legacy "${COMMON[@]}" \
  --source="${BUILD}/cleanup_legacy" --trigger-http --no-allow-unauthenticated

echo ""
echo "BASE_URL=$(gcloud functions describe sta-tasks-api --gen2 --region="${GCP_REGION}" --project="${GCP_PROJECT}" --format='value(serviceConfig.uri)')"
