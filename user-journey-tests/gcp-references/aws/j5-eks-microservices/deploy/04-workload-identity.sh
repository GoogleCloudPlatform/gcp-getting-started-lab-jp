#!/usr/bin/env bash
# 04-workload-identity.sh — the IRSA translation:
#   GSA ems-booking-gsa      gets roles/datastore.user (Firestore access)
#   KSA ems/booking-api    may impersonate it (roles/iam.workloadIdentityUser)
# The KSA-side annotation is applied by k8s-overlay/render.py. Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if ! gcloud iam service-accounts describe "${GSA_EMAIL}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${GSA_NAME}" \
    --display-name="ems booking-api (Workload Identity)" --project "${GCP_PROJECT}"
fi

gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${GSA_EMAIL}" --role="roles/datastore.user" \
  --condition=None >/dev/null
echo "granted roles/datastore.user to ${GSA_EMAIL}"

gcloud iam service-accounts add-iam-policy-binding "${GSA_EMAIL}" \
  --project "${GCP_PROJECT}" \
  --member="serviceAccount:${GCP_PROJECT}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]" \
  --role="roles/iam.workloadIdentityUser" >/dev/null
echo "bound KSA ${K8S_NAMESPACE}/${KSA_NAME} -> ${GSA_EMAIL}"
