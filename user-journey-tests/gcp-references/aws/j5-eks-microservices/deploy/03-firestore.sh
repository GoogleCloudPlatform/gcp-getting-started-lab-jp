#!/usr/bin/env bash
# 03-firestore.sh — named Firestore database (keeps the shared project clean,
# consistent with the other journey references). Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if gcloud firestore databases describe --database="${FIRESTORE_DB}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo "firestore db ${FIRESTORE_DB} exists"
else
  gcloud firestore databases create --database="${FIRESTORE_DB}" \
    --location="${GCP_REGION}" --type=firestore-native --project "${GCP_PROJECT}"
fi
