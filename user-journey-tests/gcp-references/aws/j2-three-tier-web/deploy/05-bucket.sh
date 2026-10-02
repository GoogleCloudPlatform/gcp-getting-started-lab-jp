#!/usr/bin/env bash
# 05-bucket.sh — the assets bucket (S3 ttw-assets-<account> analogue):
# private, uniform bucket-level access, holds app/app.tar.gz + covers/*.png.
# ttw-app-sa gets objectViewer on THIS bucket only (instances read the bundle
# at boot and stream covers at runtime — they never write).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project "${GCP_PROJECT}" \
    --location="${GCP_REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
else
  echo "Bucket gs://${BUCKET_NAME} already exists."
fi

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --project "${GCP_PROJECT}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/storage.objectViewer >/dev/null

echo "Bucket ready: gs://${BUCKET_NAME}"
