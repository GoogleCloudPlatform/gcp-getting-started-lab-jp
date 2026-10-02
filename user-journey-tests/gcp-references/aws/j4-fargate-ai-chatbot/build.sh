#!/usr/bin/env bash
# build.sh — assemble and push the GCP fac-api image.
# -----------------------------------------------------------------------------
# 1. Copies user-journey-tests/aws/j4-fargate-ai-chatbot/app/ into a temp staging dir
# 2. Applies app-overlay/ on top (main.py, llm.py, gcp_clients.py, requirements)
# 3. Removes the now-dead AWS funnel (aws_clients.py) so the image is boto3-free
# 4. docker build + push to Artifact Registry
#
# The Dockerfile is reused UNCHANGED from the journey app (it COPYs *.py and
# honors $PORT, which Cloud Run injects).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/deploy/00-vars.sh"

JOURNEY_APP="${SCRIPT_DIR}/../../../../user-journey-tests/aws/j4-fargate-ai-chatbot/app"
OVERLAY="${SCRIPT_DIR}/app-overlay"

if [[ ! -d "$JOURNEY_APP" ]]; then
  echo "FATAL: journey app not found at $JOURNEY_APP" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -r "${JOURNEY_APP}/." "$STAGE/"
cp -r "${OVERLAY}/." "$STAGE/"
rm -f "${STAGE}/aws_clients.py"

echo ">>> Staged image context:"
ls -1 "$STAGE"

# Docker credential helper for Artifact Registry (idempotent).
gcloud auth configure-docker "${AR_HOST}" --quiet --project "${GCP_PROJECT}"

echo ">>> Building ${IMAGE_URI}"
docker build --platform linux/amd64 -t "${IMAGE_URI}" "$STAGE"
docker push "${IMAGE_URI}"

echo ">>> Pushed ${IMAGE_URI}"
