#!/usr/bin/env bash
# 99-teardown.sh — remove every j4-fargate-ai-chatbot GCP reference resource.
# Confirmation-gated (type "yes", or FORCE_TEARDOWN=1). Reverse deploy order;
# every step is skip-if-absent so partial teardowns can be re-run.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  echo "About to DELETE all j4-fargate-ai-chatbot reference resources in project ${GCP_PROJECT}."
  read -r -p 'Type "yes" to continue: ' CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted (nothing deleted)."
    exit 1
  fi
fi

# 1. Cloud Run service
if gcloud run services describe "${SERVICE_NAME}" --region "${GCP_REGION}" \
    --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud run services delete "${SERVICE_NAME}" \
    --region "${GCP_REGION}" --project "${GCP_PROJECT}" --quiet
  echo ">>> Deleted Cloud Run service ${SERVICE_NAME}"
else
  echo ">>> Cloud Run service ${SERVICE_NAME} not found, skipping"
fi

# 2. Artifact Registry repo (removes all images in it)
if gcloud artifacts repositories describe "${AR_REPO}" --location "${GCP_REGION}" \
    --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud artifacts repositories delete "${AR_REPO}" \
    --location "${GCP_REGION}" --project "${GCP_PROJECT}" --quiet
  echo ">>> Deleted Artifact Registry repo ${AR_REPO}"
else
  echo ">>> Artifact Registry repo ${AR_REPO} not found, skipping"
fi

# 3. Transcript bucket (objects + bucket)
if gcloud storage buckets describe "gs://${BUCKET_NAME}" \
    --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud storage rm --recursive "gs://${BUCKET_NAME}" --project "${GCP_PROJECT}"
  echo ">>> Deleted gs://${BUCKET_NAME}"
else
  echo ">>> Bucket gs://${BUCKET_NAME} not found, skipping"
fi

# 4. Service account (project bindings first, then the SA)
if gcloud iam service-accounts describe "${SA_EMAIL}" \
    --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  for role in roles/datastore.user roles/aiplatform.user; do
    gcloud projects remove-iam-policy-binding "${GCP_PROJECT}" \
      --member "serviceAccount:${SA_EMAIL}" \
      --role "${role}" \
      --condition None \
      --project "${GCP_PROJECT}" >/dev/null 2>&1 || true
  done
  gcloud iam service-accounts delete "${SA_EMAIL}" \
    --project "${GCP_PROJECT}" --quiet
  echo ">>> Deleted service account ${SA_EMAIL}"
else
  echo ">>> Service account ${SA_EMAIL} not found, skipping"
fi

# 5. Firestore named database
if gcloud firestore databases describe --database="${FIRESTORE_DB}" \
    --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud firestore databases delete --database="${FIRESTORE_DB}" \
    --project "${GCP_PROJECT}" --quiet
  echo ">>> Deleted Firestore database ${FIRESTORE_DB}"
else
  echo ">>> Firestore database ${FIRESTORE_DB} not found, skipping"
fi

echo ""
echo "j4-fargate-ai-chatbot GCP reference teardown complete."
