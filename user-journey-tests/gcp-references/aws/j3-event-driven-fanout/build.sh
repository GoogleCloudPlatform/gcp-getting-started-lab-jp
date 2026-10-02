#!/usr/bin/env bash
# build.sh — assemble Cloud Run functions source dirs: overlay handlers +
# flattened gcpClients funnel + package.json. (The journey app's business
# logic is fully re-expressed in the overlay handlers, which mirror it
# line-for-line; nothing AWS-flavored ships to GCP.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERLAY="${SCRIPT_DIR}/app-overlay"
BUILD="${SCRIPT_DIR}/build"

rm -rf "$BUILD"
for fn in worker digest; do
  mkdir -p "${BUILD}/${fn}"
  cp "${OVERLAY}/${fn}/index.mjs" "${BUILD}/${fn}/index.mjs"
  cp "${OVERLAY}/shared/gcpClients.mjs" "${BUILD}/${fn}/gcpClients.mjs"
  cp "${OVERLAY}/package.json" "${BUILD}/${fn}/package.json"
done
echo "Function sources assembled under ${BUILD}/"
