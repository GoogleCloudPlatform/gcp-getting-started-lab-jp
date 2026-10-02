#!/usr/bin/env bash
# 03-scheduler.sh — Cloud Scheduler job invoking sta-export-worker via OIDC.
# Mirrors the EventBridge cron(0 0 * * ? *). Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

SA_EMAIL="${SCHEDULER_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SCHEDULER_SA}" \
    --display-name="Task-reminder scheduler invoker" --project "${GCP_PROJECT}"
fi

WORKER_URL=$(gcloud functions describe sta-export-worker --gen2 \
  --region="${GCP_REGION}" --project="${GCP_PROJECT}" --format='value(serviceConfig.uri)')

# invoker on the worker's underlying Cloud Run service
gcloud run services add-iam-policy-binding sta-export-worker \
  --region="${GCP_REGION}" --project="${GCP_PROJECT}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/run.invoker" >/dev/null

if gcloud scheduler jobs describe sta-daily-export --location="${GCP_REGION}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud scheduler jobs update http sta-daily-export \
    --location="${GCP_REGION}" --project="${GCP_PROJECT}" \
    --schedule="0 0 * * *" --time-zone="Etc/UTC" \
    --uri="${WORKER_URL}" --http-method=POST \
    --oidc-service-account-email="${SA_EMAIL}"
else
  gcloud scheduler jobs create http sta-daily-export \
    --location="${GCP_REGION}" --project="${GCP_PROJECT}" \
    --schedule="0 0 * * *" --time-zone="Etc/UTC" \
    --uri="${WORKER_URL}" --http-method=POST \
    --oidc-service-account-email="${SA_EMAIL}"
fi
echo "scheduler job sta-daily-export ready"
