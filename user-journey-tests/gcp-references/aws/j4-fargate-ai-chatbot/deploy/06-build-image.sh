#!/usr/bin/env bash
# 06-build-image.sh — build + push the image (journey app + GCP overlay).
# Thin wrapper: the copy/overlay/build/push logic lives in ../build.sh.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/../build.sh"
