#!/usr/bin/env bash
# 01-services.sh — enable the APIs this reference touches (idempotent).

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/00-env.sh"

gcloud services enable \
  aiplatform.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  --project "${GCP_PROJECT}"
echo "APIs enabled on ${GCP_PROJECT}."
