#!/usr/bin/env bash
# 99-teardown.sh — remove the j1-serverless-task-api GCP reference. Gated.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p "Type 'yes' to destroy j1-serverless-task-api reference in ${GCP_PROJECT}: " answer
  [[ "$answer" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

gcloud scheduler jobs delete sta-daily-export --location="${GCP_REGION}" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
for fn in sta-tasks-api sta-export-worker sta-cleanup-legacy; do
  gcloud functions delete "$fn" --gen2 --region="${GCP_REGION}" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
done
gcloud storage rm -r "gs://${BUCKET}" --project="${GCP_PROJECT}" 2>/dev/null || true
gcloud firestore databases delete --database="${FIRESTORE_DB}" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
gcloud iam service-accounts delete "${SCHEDULER_SA}@${GCP_PROJECT}.iam.gserviceaccount.com" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
echo "j1-serverless-task-api GCP reference torn down."
