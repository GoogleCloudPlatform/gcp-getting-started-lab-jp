#!/usr/bin/env bash
# build.sh — build both service images and push to Artifact Registry.
# catalog-api ships unchanged (pure stdlib Go, no cloud SDK calls).
# booking-api gets the overlay: awsClients.mjs (Firestore port) + package.json.
set -euo pipefail
source "$(dirname "$0")/deploy/00-vars.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JOURNEY="${SCRIPT_DIR}/../../../../user-journey-tests/aws/j5-eks-microservices"
STAGE="${SCRIPT_DIR}/build"

[[ -d "$JOURNEY" ]] || { echo "FATAL: journey dir not found: $JOURNEY" >&2; exit 1; }

gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet --project "${GCP_PROJECT}"

rm -rf "$STAGE"
mkdir -p "$STAGE"

# catalog-api: verbatim copy
cp -r "${JOURNEY}/app/catalog-api" "${STAGE}/catalog-api"

# booking-api: journey app + overlay (funnel + deps swapped, server.mjs untouched)
cp -r "${JOURNEY}/app/booking-api" "${STAGE}/booking-api"
rm -f "${STAGE}/booking-api/package-lock.json"
cp "${SCRIPT_DIR}/app-overlay/booking-api/awsClients.mjs" "${STAGE}/booking-api/awsClients.mjs"
cp "${SCRIPT_DIR}/app-overlay/booking-api/package.json" "${STAGE}/booking-api/package.json"
# the journey Dockerfile runs npm ci, which needs a lock matching the
# overlaid package.json — regenerate it for the GCP dependency set
(cd "${STAGE}/booking-api" && npm install --package-lock-only --no-audit --no-fund >/dev/null)

for svc in catalog-api booking-api; do
  IMG="${AR_PREFIX}/ems-${svc}:${IMAGE_TAG}"
  echo ">>> building ${IMG}"
  docker build -t "${IMG}" "${STAGE}/${svc}"
  docker push "${IMG}"
done
echo "images pushed to ${AR_PREFIX}"
