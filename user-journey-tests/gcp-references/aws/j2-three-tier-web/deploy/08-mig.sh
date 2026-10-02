#!/usr/bin/env bash
# 08-mig.sh — instance template + managed instance group (the ASG analogue):
# 2x e2-micro Debian 12, tag ttw-app, service account ttw-app-sa, startup
# script = deploy/startup-script.sh (pull bundle from GCS, venv install,
# Cloud SQL Auth Proxy sidecar, gunicorn :8000 under systemd).
#
# Instance templates are immutable: if startup-script.sh changes, delete the
# template (99-teardown.sh or manually) or bump TEMPLATE_NAME, then re-run.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if ! gcloud compute instance-templates describe "${TEMPLATE_NAME}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute instance-templates create "${TEMPLATE_NAME}" \
    --project "${GCP_PROJECT}" \
    --machine-type=e2-micro \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=ttw-app \
    --service-account="${SA_EMAIL}" \
    --scopes=cloud-platform \
    --metadata-from-file=startup-script="${SCRIPT_DIR}/startup-script.sh" \
    --labels=journey=j2-three-tier-web,owner=migration-test
else
  echo "Instance template ${TEMPLATE_NAME} already exists."
fi

if ! gcloud compute instance-groups managed describe "${MIG_NAME}" --zone "${GCP_ZONE}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute instance-groups managed create "${MIG_NAME}" \
    --project "${GCP_PROJECT}" \
    --zone "${GCP_ZONE}" \
    --template "${TEMPLATE_NAME}" \
    --size "${MIG_SIZE}"
else
  echo "MIG ${MIG_NAME} already exists."
fi

# Named port so the backend service can address "http" -> 8000. Safe to re-run.
gcloud compute instance-groups managed set-named-ports "${MIG_NAME}" \
  --project "${GCP_PROJECT}" \
  --zone "${GCP_ZONE}" \
  --named-ports=http:8000

echo ">>> Waiting for the MIG to report stable (first boot installs packages — a few minutes)"
gcloud compute instance-groups managed wait-until "${MIG_NAME}" \
  --stable \
  --zone "${GCP_ZONE}" \
  --project "${GCP_PROJECT}" \
  --timeout=900

echo "MIG ready: ${MIG_NAME} (${MIG_SIZE}x e2-micro in ${GCP_ZONE})"
