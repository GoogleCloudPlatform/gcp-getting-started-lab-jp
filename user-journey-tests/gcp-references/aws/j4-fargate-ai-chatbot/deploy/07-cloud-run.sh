#!/usr/bin/env bash
# 07-cloud-run.sh — deploy the fac-api Cloud Run service (idempotent:
# `gcloud run deploy` creates or revises in place).
#
# PORT is NOT set here — Cloud Run reserves and injects it, and the
# journey Dockerfile's CMD already binds to $PORT.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

gcloud run deploy "${SERVICE_NAME}" \
  --image "${IMAGE_URI}" \
  --region "${GCP_REGION}" \
  --service-account "${SA_EMAIL}" \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 2 \
  --memory 512Mi \
  --cpu 1 \
  --set-env-vars "TABLE_NAME=${FIRESTORE_DB},BUCKET=${BUCKET_NAME},MODEL_ID=${MODEL_ID},LLM_MODE=live,GOOGLE_CLOUD_PROJECT=${GCP_PROJECT},VERTEX_LOCATION=${VERTEX_LOCATION}" \
  --project "${GCP_PROJECT}"

URL=$(gcloud run services describe "${SERVICE_NAME}" \
  --region "${GCP_REGION}" \
  --project "${GCP_PROJECT}" \
  --format 'value(status.url)')

echo ""
echo "============================================================"
echo ">>> fac-api deployed on Cloud Run (LLM_MODE=live, ${MODEL_ID})"
echo "BASE_URL=${URL}"
echo ""
echo "Parity check with the journey's UNMODIFIED smoke test:"
echo "  ../../../../user-journey-tests/aws/j4-fargate-ai-chatbot/scripts/smoke-test.sh ${URL}"
echo "============================================================"
