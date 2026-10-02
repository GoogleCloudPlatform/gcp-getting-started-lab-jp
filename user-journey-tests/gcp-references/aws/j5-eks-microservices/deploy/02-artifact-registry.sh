#!/usr/bin/env bash
# 02-artifact-registry.sh — docker repo for both service images. Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if gcloud artifacts repositories describe "${AR_REPO}" --location "${GCP_REGION}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo "repo ${AR_REPO} exists"
else
  gcloud artifacts repositories create "${AR_REPO}" \
    --repository-format=docker --location "${GCP_REGION}" \
    --project "${GCP_PROJECT}" \
    --description="Equipment-marketplace images (j5 GCP reference)"
fi
