#!/usr/bin/env bash
# 01-cluster.sh — GKE Autopilot regional cluster (takes ~10-15 min). Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if gcloud container clusters describe "${CLUSTER}" --region "${GCP_REGION}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo "cluster ${CLUSTER} exists"
else
  gcloud container clusters create-auto "${CLUSTER}" \
    --region "${GCP_REGION}" --project "${GCP_PROJECT}" \
    --release-channel regular
fi

gcloud container clusters describe "${CLUSTER}" --region "${GCP_REGION}" \
  --project "${GCP_PROJECT}" --format='value(status)'
