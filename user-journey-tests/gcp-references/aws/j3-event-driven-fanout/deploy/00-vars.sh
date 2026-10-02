#!/usr/bin/env bash
# 00-vars.sh — shared variables for the j3-event-driven-fanout GCP reference.
set -euo pipefail

export GCP_PROJECT="${GCP_PROJECT:-aws-migration-501814}"
export GCP_REGION="${GCP_REGION:-asia-northeast1}"
export BUCKET="edf-uploads-${GCP_PROJECT}"
export FIRESTORE_DB="edf-photos"
export MODERATION_TOPIC="edf-moderation-alerts"
export SCHEDULER_SA="edf-scheduler"
export SCHEDULER_SA_EMAIL="${SCHEDULER_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"

echo "project=${GCP_PROJECT} region=${GCP_REGION} bucket=${BUCKET} db=${FIRESTORE_DB}"
