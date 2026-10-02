#!/usr/bin/env bash
# 01-data.sh — bucket, named Firestore DB, moderation topic (NO subscription:
# the subscription-less topic is part of the source system's story and is
# mirrored faithfully). Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if ! gcloud storage buckets describe "gs://${BUCKET}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET}" \
    --location="${GCP_REGION}" --uniform-bucket-level-access --project "${GCP_PROJECT}"
else
  echo "bucket ${BUCKET} exists"
fi

if ! gcloud firestore databases describe --database="${FIRESTORE_DB}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud firestore databases create --database="${FIRESTORE_DB}" \
    --location="${GCP_REGION}" --type=firestore-native --project "${GCP_PROJECT}"
else
  echo "firestore db ${FIRESTORE_DB} exists"
fi

if ! gcloud pubsub topics describe "${MODERATION_TOPIC}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud pubsub topics create "${MODERATION_TOPIC}" --project "${GCP_PROJECT}"
else
  echo "topic ${MODERATION_TOPIC} exists"
fi
