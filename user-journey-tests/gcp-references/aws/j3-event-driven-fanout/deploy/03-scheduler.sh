#!/usr/bin/env bash
# 03-scheduler.sh — nightly Cloud Scheduler job for the digest (OIDC), the
# EventBridge rate(1 day) replacement. Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if ! gcloud iam service-accounts describe "${SCHEDULER_SA_EMAIL}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SCHEDULER_SA}" \
    --display-name="Photo-pipeline digest invoker" --project "${GCP_PROJECT}"
fi

DIGEST_URL=$(gcloud functions describe edf-digest --gen2 \
  --region="${GCP_REGION}" --project="${GCP_PROJECT}" --format='value(serviceConfig.uri)')

gcloud run services add-iam-policy-binding edf-digest \
  --region="${GCP_REGION}" --project="${GCP_PROJECT}" \
  --member="serviceAccount:${SCHEDULER_SA_EMAIL}" --role="roles/run.invoker" >/dev/null

if gcloud scheduler jobs describe edf-nightly-digest --location="${GCP_REGION}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud scheduler jobs update http edf-nightly-digest \
    --location="${GCP_REGION}" --project="${GCP_PROJECT}" \
    --schedule="0 0 * * *" --time-zone="Etc/UTC" \
    --uri="${DIGEST_URL}" --http-method=POST \
    --oidc-service-account-email="${SCHEDULER_SA_EMAIL}"
else
  gcloud scheduler jobs create http edf-nightly-digest \
    --location="${GCP_REGION}" --project="${GCP_PROJECT}" \
    --schedule="0 0 * * *" --time-zone="Etc/UTC" \
    --uri="${DIGEST_URL}" --http-method=POST \
    --oidc-service-account-email="${SCHEDULER_SA_EMAIL}"
fi
echo "scheduler job edf-nightly-digest ready"
