#!/usr/bin/env bash
# 00-vars.sh — shared variables for the j1-serverless-task-api GCP reference.
# Source this from every other numbered script.
set -euo pipefail

export GCP_PROJECT="${GCP_PROJECT:-aws-migration-501814}"
export GCP_REGION="${GCP_REGION:-asia-northeast1}"
export FIRESTORE_DB="sta-tasks"
export BUCKET="sta-exports-${GCP_PROJECT}"

# Runtime SA shared by the three functions (per-function IAM roles on AWS
# collapse to one least-privilege runtime identity here).
export RUNTIME_SA="sta-fn"
export RUNTIME_SA_EMAIL="${RUNTIME_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"
# Scheduler-side identity that mints OIDC tokens for the export worker.
export SCHEDULER_SA="sta-scheduler"
export SCHEDULER_SA_EMAIL="${SCHEDULER_SA}@${GCP_PROJECT}.iam.gserviceaccount.com"

echo "project=${GCP_PROJECT} region=${GCP_REGION} db=${FIRESTORE_DB} bucket=${BUCKET}"
