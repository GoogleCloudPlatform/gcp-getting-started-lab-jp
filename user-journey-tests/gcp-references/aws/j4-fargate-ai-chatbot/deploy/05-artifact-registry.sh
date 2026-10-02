#!/usr/bin/env bash
# 05-artifact-registry.sh — docker repo for the fac-api image (idempotent).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if gcloud artifacts repositories describe "${AR_REPO}" \
    --location "${GCP_REGION}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo ">>> Artifact Registry repo ${AR_REPO} already exists"
else
  gcloud artifacts repositories create "${AR_REPO}" \
    --repository-format=docker \
    --location "${GCP_REGION}" \
    --description "j4-fargate-ai-chatbot reference images" \
    --project "${GCP_PROJECT}"
  echo ">>> Created Artifact Registry repo ${AR_REPO} in ${GCP_REGION}"
fi
