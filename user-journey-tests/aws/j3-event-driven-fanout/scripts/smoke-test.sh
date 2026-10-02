#!/usr/bin/env bash
# smoke-test.sh aws|gcp — end-to-end pipeline check (provider-arg mode: this
# journey has no HTTP edge). Uploads a uniquely-keyed fixture, then verifies:
#   1. metadata record appears in the photo store (poll up to 60s)
#   2. thumbnails/ copy exists
#   3. (aws) DLQ is empty — nothing poisoned
# The SAME script must pass against the AWS deployment and any migrated one.
set -uo pipefail

MODE="${1:?Usage: smoke-test.sh aws|gcp}"
FAILURES=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

STAMP=$(date +%s)
KEY="incoming/smoke-${STAMP}.png"
BASENAME="smoke-${STAMP}.png"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
python3 -c "import base64,sys; open(sys.argv[1],'wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))" "$TMP/fixture.png"

if [[ "$MODE" == "aws" ]]; then
  ENV_FILE="${HOME}/.aws/journeys.env"
  # shellcheck disable=SC1090
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
  : "${AWS_REGION:=ap-northeast-1}"
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  BUCKET="edf-uploads-${ACCOUNT_ID}"
  TABLE="edf-photos"

  aws s3 cp "$TMP/fixture.png" "s3://${BUCKET}/${KEY}" --content-type image/png >/dev/null \
    && pass "uploaded ${KEY}" || fail "upload failed"

  FOUND=""
  for _ in $(seq 1 20); do
    ITEM=$(aws dynamodb get-item --region "$AWS_REGION" --table-name "$TABLE" \
      --key "{\"object_key\":{\"S\":\"${KEY}\"}}" --query 'Item.sha256.S' --output text 2>/dev/null)
    if [[ -n "$ITEM" && "$ITEM" != "None" ]]; then FOUND="$ITEM"; break; fi
    sleep 3
  done
  [[ -n "$FOUND" ]] && pass "metadata row present (sha256 ${FOUND:0:12}…)" || fail "no metadata row within 60s"

  aws s3api head-object --bucket "$BUCKET" --key "thumbnails/${BASENAME}" >/dev/null 2>&1 \
    && pass "thumbnails/ copy exists" || fail "thumbnails/ copy missing"

  DLQ_URL=$(aws sqs get-queue-url --region "$AWS_REGION" --queue-name edf-thumbnails-dlq --query QueueUrl --output text)
  DLQ_N=$(aws sqs get-queue-attributes --region "$AWS_REGION" --queue-url "$DLQ_URL" \
    --attribute-names ApproximateNumberOfMessages \
    --query 'Attributes.ApproximateNumberOfMessages' --output text)
  [[ "$DLQ_N" == "0" ]] && pass "DLQ empty" || fail "DLQ has ${DLQ_N} messages"

elif [[ "$MODE" == "gcp" ]]; then
  GCP_PROJECT="${GCP_PROJECT:-aws-migration-501814}"
  BUCKET="edf-uploads-${GCP_PROJECT}"
  DB="edf-photos"

  gcloud storage cp "$TMP/fixture.png" "gs://${BUCKET}/${KEY}" \
    --content-type=image/png --project "$GCP_PROJECT" >/dev/null 2>&1 \
    && pass "uploaded ${KEY}" || fail "upload failed"

  DOC_ID=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(urllib.parse.quote(sys.argv[1], safe=''), safe=''))" "$KEY")
  TOKEN=$(gcloud auth print-access-token)
  FOUND=""
  for _ in $(seq 1 20); do
    CODE=$(curl -s -o "$TMP/doc.json" -w '%{http_code}' \
      -H "Authorization: Bearer ${TOKEN}" \
      "https://firestore.googleapis.com/v1/projects/${GCP_PROJECT}/databases/${DB}/documents/edf-photos/${DOC_ID}")
    if [[ "$CODE" == "200" ]]; then FOUND=yes; break; fi
    sleep 3
  done
  [[ -n "$FOUND" ]] && pass "metadata document present" || fail "no metadata document within 60s"

  gcloud storage objects describe "gs://${BUCKET}/thumbnails/${BASENAME}" --project "$GCP_PROJECT" >/dev/null 2>&1 \
    && pass "thumbnails/ copy exists" || fail "thumbnails/ copy missing"

  pass "DLQ check n/a on this provider (no DLQ in the reference pipeline)"
else
  echo "FAIL: unknown mode '$MODE' (use aws|gcp)"; exit 1
fi

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "SMOKE TEST PASSED (${MODE})"
  exit 0
fi
echo "SMOKE TEST FAILED (${FAILURES} failing, ${MODE})"
exit 1
