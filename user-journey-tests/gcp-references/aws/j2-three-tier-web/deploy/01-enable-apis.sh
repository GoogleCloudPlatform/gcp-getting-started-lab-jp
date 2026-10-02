#!/usr/bin/env bash
# 01-enable-apis.sh — enable every API the ttw reference touches. Idempotent
# (services enable is a no-op when already on).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

gcloud services enable \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  monitoring.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project "${GCP_PROJECT}"

echo "APIs enabled on ${GCP_PROJECT}."
