#!/usr/bin/env bash
# seed.sh — drop 3 deterministic fixtures into incoming/ to exercise the
# pipeline: two tiny PNGs (happy path) and one text file (moderation path).
set -euo pipefail

ENV_FILE="${HOME}/.aws/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_ACCOUNT_ID)" >&2
  exit 1
fi
: "${EXPECTED_ACCOUNT_ID:?Set EXPECTED_ACCOUNT_ID in ~/.aws/journeys.env}"
: "${AWS_REGION:=ap-northeast-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got ${ACCOUNT_ID}, expected ${EXPECTED_ACCOUNT_ID})" >&2
  exit 1
fi

BUCKET="edf-uploads-${ACCOUNT_ID}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1x1 px PNGs (red / blue), deterministic bytes
python3 - "$TMP" <<'EOF'
import base64, pathlib, sys
tmp = pathlib.Path(sys.argv[1])
red = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
blue = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
(tmp / "hero-cat.png").write_bytes(base64.b64decode(red))
(tmp / "sunset-beach.png").write_bytes(base64.b64decode(blue))
(tmp / "notes.txt").write_text("photo-pipeline seed fixture: this is not an image\n")
EOF

aws s3 cp "$TMP/hero-cat.png" "s3://${BUCKET}/incoming/hero-cat.png" --content-type image/png
aws s3 cp "$TMP/sunset-beach.png" "s3://${BUCKET}/incoming/sunset-beach.png" --content-type image/png
aws s3 cp "$TMP/notes.txt" "s3://${BUCKET}/incoming/notes.txt" --content-type text/plain
echo "Seeded 3 fixtures into s3://${BUCKET}/incoming/"
