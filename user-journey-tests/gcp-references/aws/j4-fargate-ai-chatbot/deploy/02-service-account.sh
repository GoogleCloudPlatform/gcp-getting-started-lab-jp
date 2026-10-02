#!/usr/bin/env bash
# 02-service-account.sh — runtime SA for the Cloud Run service (idempotent).
#
# Grants (mirrors the AWS task role's scope):
#   roles/datastore.user   project-level  -> Firestore turn CRUD
#   roles/aiplatform.user  project-level  -> Gemini generate/count-tokens
#   (bucket-scoped objectAdmin is granted in 04-bucket.sh, after the bucket exists)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if ! gcloud iam service-accounts describe "${SA_EMAIL}" \
    --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name "fac-api runtime (j4-fargate-ai-chatbot reference)" \
    --project "${GCP_PROJECT}"
else
  echo ">>> Service account ${SA_EMAIL} already exists"
fi

# add-iam-policy-binding is a no-op when the binding already exists.
for role in roles/datastore.user roles/aiplatform.user; do
  gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
    --member "serviceAccount:${SA_EMAIL}" \
    --role "${role}" \
    --condition None \
    --project "${GCP_PROJECT}" >/dev/null
  echo ">>> Granted ${role} to ${SA_EMAIL}"
done
