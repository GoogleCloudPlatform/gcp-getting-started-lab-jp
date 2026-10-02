#!/usr/bin/env bash
# 03-firestore.sh — named Firestore database for conversation turns (idempotent).
#
# A NAMED database (fac-conversations) rather than (default): the shared
# harness project may already have a default DB in another location/mode,
# and the app's TABLE_NAME env var maps cleanly onto a database id.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if gcloud firestore databases describe --database="${FIRESTORE_DB}" \
    --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo ">>> Firestore database ${FIRESTORE_DB} already exists"
else
  gcloud firestore databases create \
    --database="${FIRESTORE_DB}" \
    --location="${GCP_REGION}" \
    --type=firestore-native \
    --project "${GCP_PROJECT}"
  echo ">>> Created Firestore database ${FIRESTORE_DB} in ${GCP_REGION}"
fi
