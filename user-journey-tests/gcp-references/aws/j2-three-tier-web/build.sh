#!/usr/bin/env bash
# build.sh — assemble the GCP app bundle for j2-three-tier-web.
# -----------------------------------------------------------------------------
# Copies the journey app, applies app-overlay/ on top (gcp_clients.py, the
# aws_clients.py compatibility shim, the proxy-aware db.py, GCP
# requirements.txt), and produces:
#
#   dist/app.tar.gz   uploaded to gs://ttw-assets-<project>/app/ by deploy/06
#   dist/covers/      the same 12 deterministic PNGs the AWS side uses
#                     (generated with the journey's own make-covers.py)
#
# No cloud calls here — deploy/06-bundle.sh does the upload.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
JOURNEY_APP="${REPO_ROOT}/user-journey-tests/aws/j2-three-tier-web/app"
JOURNEY_SCRIPTS="${REPO_ROOT}/user-journey-tests/aws/j2-three-tier-web/scripts"
OVERLAY="${SCRIPT_DIR}/app-overlay"
DIST="${SCRIPT_DIR}/dist"

[[ -d "$JOURNEY_APP" ]] || { echo "FATAL: journey app not found at $JOURNEY_APP" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# 1. journey app as the base, overlay on top (overlay wins on collisions).
cp -r "$JOURNEY_APP/." "$STAGE/"
cp -r "$OVERLAY/." "$STAGE/"

# 2. bundle + deterministic covers. Local byte-caches stay out so the
# bundle content is deterministic.
tar czf "${DIST}/app.tar.gz" --exclude='__pycache__' --exclude='*.pyc' -C "$STAGE" .
python3 "${JOURNEY_SCRIPTS}/make-covers.py" "${DIST}/covers"

echo "Built:"
echo "  ${DIST}/app.tar.gz"
echo "  ${DIST}/covers/ (12 PNGs)"
