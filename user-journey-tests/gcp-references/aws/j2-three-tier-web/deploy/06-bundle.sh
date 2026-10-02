#!/usr/bin/env bash
# 06-bundle.sh — build the GCP app bundle (journey app + overlay) and upload
# it plus the 12 deterministic covers to the assets bucket. Re-runnable; note
# that MIG instances only read the bundle at BOOT, so after re-uploading run:
#   gcloud compute instance-groups managed rolling-action replace ttw-mig \
#     --zone <zone> --project <project>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

REF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

"${REF_DIR}/build.sh"

gcloud storage cp "${REF_DIR}/dist/app.tar.gz" "gs://${BUCKET_NAME}/app/app.tar.gz" \
  --project "${GCP_PROJECT}"
gcloud storage rsync "${REF_DIR}/dist/covers" "gs://${BUCKET_NAME}/covers" \
  --project "${GCP_PROJECT}"

echo "Bundle + covers uploaded to gs://${BUCKET_NAME}."
