#!/usr/bin/env bash
# 03-load-corpus.sh — load the journey's exact corpus into Cloud SQL.
#
# Runs the staged project's own `python -m policyapi.bootstrap` (the file is
# copied VERBATIM from the journey by ../build.sh) from this box over the
# instance's public IP, with KB_CONNECTION_JSON read from the secret — the
# same delivery path the deployed engine uses. Re-runs reload the corpus.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/00-env.sh"

[[ -d "${STAGE_DIR}" ]] || { echo "FATAL: run ../build.sh first" >&2; exit 1; }

KB_CONNECTION_JSON="$(gcloud secrets versions access latest --secret="${KB_SECRET}" --project "${GCP_PROJECT}")"
export KB_CONNECTION_JSON

(cd "${STAGE_DIR}" && uv run python -m policyapi.bootstrap)
echo "Corpus loaded."
