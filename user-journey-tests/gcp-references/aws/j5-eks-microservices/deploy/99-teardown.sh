#!/usr/bin/env bash
# 99-teardown.sh — remove the j5 GCP reference. Gated.
# Deleting the cluster also deletes the LoadBalancer it provisioned.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p "Type 'yes' to destroy j5-eks-microservices reference in ${GCP_PROJECT}: " answer
  [[ "$answer" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

gcloud container clusters delete "${CLUSTER}" --region "${GCP_REGION}" --project "${GCP_PROJECT}" --quiet 2>/dev/null || true
gcloud artifacts repositories delete "${AR_REPO}" --location "${GCP_REGION}" --project "${GCP_PROJECT}" --quiet 2>/dev/null || true
gcloud firestore databases delete --database="${FIRESTORE_DB}" --project "${GCP_PROJECT}" --quiet 2>/dev/null || true
gcloud iam service-accounts delete "${GSA_EMAIL}" --project "${GCP_PROJECT}" --quiet 2>/dev/null || true
echo "j5-eks-microservices GCP reference torn down."
