#!/usr/bin/env bash
# build.sh — assemble per-function Cloud Run functions source dirs:
# 1. copy the journey app (function dir + shared funnel) into build/<fn>/
# 2. apply this overlay on top (main.py, gcp_clients.py, requirements.txt)
# 3. drop the AWS-only files (handler.py, aws_clients.py) so the upload is
#    boto3-free
# Output: build/<fn>/ ready for `gcloud functions deploy --source`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JOURNEY="${SCRIPT_DIR}/../../../../user-journey-tests/aws/j1-serverless-task-api"
OVERLAY="${SCRIPT_DIR}/app-overlay"
BUILD="${SCRIPT_DIR}/build"

[[ -d "$JOURNEY" ]] || { echo "FATAL: journey dir not found: $JOURNEY" >&2; exit 1; }

rm -rf "$BUILD"
for fn in tasks_api export_worker cleanup_legacy; do
  stage="${BUILD}/${fn}"
  mkdir -p "$stage"

  # 1) journey app: the per-function dir plus the shared AWS funnel
  cp -r "${JOURNEY}/app/functions/${fn}/." "$stage/"
  cp "${JOURNEY}/app/shared/aws_clients.py" "$stage/"

  # 2) overlay: GCP ports replace the Lambda handler and the funnel
  cp "${OVERLAY}/functions/${fn}/main.py" "$stage/main.py"
  cp "${OVERLAY}/shared/gcp_clients.py" "$stage/gcp_clients.py"
  cp "${OVERLAY}/requirements.txt" "$stage/requirements.txt"

  # 3) remove the AWS-only files and local build junk
  rm -f "$stage/handler.py" "$stage/aws_clients.py"
  find "$stage" -type d -name __pycache__ -prune -exec rm -rf {} +
done
echo "Function sources assembled under ${BUILD}/"
