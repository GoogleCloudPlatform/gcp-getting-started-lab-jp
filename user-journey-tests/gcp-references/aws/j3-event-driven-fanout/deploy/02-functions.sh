#!/usr/bin/env bash
# 02-functions.sh — deploy the worker (Eventarc GCS trigger) and digest (HTTP,
# auth required) functions. Includes the one-time grant Eventarc GCS triggers
# need: the Cloud Storage service agent must hold roles/pubsub.publisher.
# Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
"$(dirname "$0")/../build.sh"

BUILD="$(cd "$(dirname "$0")/.." && pwd)/build"
PROJECT_NUMBER=$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')

# GCS service agent -> pubsub.publisher (Eventarc GCS trigger prerequisite)
GCS_SA="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${GCS_SA}" --role="roles/pubsub.publisher" \
  --condition=None >/dev/null
echo "granted pubsub.publisher to GCS service agent"

# default compute SA receives the events (Eventarc trigger SA)
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${COMPUTE_SA}" --role="roles/eventarc.eventReceiver" \
  --condition=None >/dev/null

COMMON=(--gen2 --runtime=nodejs22 --region="${GCP_REGION}" --project="${GCP_PROJECT}"
        --entry-point=handler --memory=256Mi --timeout=60s
        --set-env-vars="BUCKET=${BUCKET},TABLE_NAME=edf-photos,FIRESTORE_DB=${FIRESTORE_DB},MODERATION_TOPIC=${MODERATION_TOPIC}")

# worker: fires on every object finalize in the bucket; incoming/ filter is in code
gcloud functions deploy edf-worker "${COMMON[@]}" \
  --source="${BUILD}/worker" \
  --trigger-bucket="${BUCKET}" \
  --trigger-location="${GCP_REGION}"

# digest: HTTP, scheduler-invoked only
gcloud functions deploy edf-digest "${COMMON[@]}" \
  --source="${BUILD}/digest" --trigger-http --no-allow-unauthenticated

echo "functions deployed"
