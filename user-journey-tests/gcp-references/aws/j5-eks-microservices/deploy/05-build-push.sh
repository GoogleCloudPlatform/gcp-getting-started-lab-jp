#!/usr/bin/env bash
# 05-build-push.sh — build both images (catalog verbatim, booking overlaid)
# and push to Artifact Registry. Requires docker.
set -euo pipefail
"$(dirname "$0")/../build.sh"
