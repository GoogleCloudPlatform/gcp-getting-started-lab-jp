#!/usr/bin/env bash
# 99-teardown.sh — remove the j3-event-driven-fanout GCP reference. Gated.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p "Type 'yes' to destroy j3-event-driven-fanout reference in ${GCP_PROJECT}: " answer
  [[ "$answer" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

gcloud scheduler jobs delete edf-nightly-digest --location="${GCP_REGION}" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
for fn in edf-worker edf-digest; do
  gcloud functions delete "$fn" --gen2 --region="${GCP_REGION}" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
done
gcloud pubsub topics delete "${MODERATION_TOPIC}" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
gcloud storage rm -r "gs://${BUCKET}" --project="${GCP_PROJECT}" 2>/dev/null || true
gcloud firestore databases delete --database="${FIRESTORE_DB}" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
gcloud iam service-accounts delete "${SCHEDULER_SA_EMAIL}" --project="${GCP_PROJECT}" --quiet 2>/dev/null || true
echo "j3-event-driven-fanout GCP reference torn down."
