#!/usr/bin/env bash
# 01-data.sh — required APIs + Firestore named database + exports bucket.
# Idempotent (services enable and create-if-absent are both re-run safe).
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

gcloud services enable \
  run.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  firestore.googleapis.com \
  cloudscheduler.googleapis.com \
  iamcredentials.googleapis.com \
  --project "${GCP_PROJECT}"

if ! gcloud firestore databases describe --database="${FIRESTORE_DB}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud firestore databases create --database="${FIRESTORE_DB}" \
    --location="${GCP_REGION}" --type=firestore-native --project "${GCP_PROJECT}"
else
  echo "firestore db ${FIRESTORE_DB} exists"
fi

if ! gcloud storage buckets describe "gs://${BUCKET}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET}" \
    --location="${GCP_REGION}" --uniform-bucket-level-access --project "${GCP_PROJECT}"
else
  echo "bucket ${BUCKET} exists"
fi
