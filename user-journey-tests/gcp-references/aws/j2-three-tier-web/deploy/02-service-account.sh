#!/usr/bin/env bash
# 02-service-account.sh — ttw-app-sa, the identity every MIG instance runs as
# (the GCP analogue of the journey's ttw-app-role instance role).
#
# Project-level roles here; per-resource grants happen next to the resource
# (03: secrets, 05: bucket). add-iam-policy-binding is idempotent — a
# duplicate binding is a no-op.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --project "${GCP_PROJECT}" \
    --display-name "Online shop app instances (j2 reference)"
else
  echo "Service account ${SA_EMAIL} already exists."
fi

# CloudWatch PutMetricData -> Cloud Monitoring metric writer.
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/monitoring.metricWriter \
  --condition=None >/dev/null

# The Cloud SQL Auth Proxy sidecar needs the client role to open tunnels.
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role roles/cloudsql.client \
  --condition=None >/dev/null

echo "ttw-app-sa ready: ${SA_EMAIL}"
