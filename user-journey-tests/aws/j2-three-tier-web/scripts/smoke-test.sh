#!/usr/bin/env bash
# smoke-test.sh — end-to-end verification of a deployed online shop.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#        e.g. ./scripts/smoke-test.sh http://ttw-alb-123.ap-northeast-1.elb.amazonaws.com
#
# Prints one "PASS: ..." / "FAIL: ..." line per check and exits non-zero if
# ANY check fails. Deliberately cloud-agnostic: it only speaks HTTP to the
# public endpoint, so the same script verifies the current deployment AND any
# future re-platformed one. Requires curl + python3.
#
# Checks:
#   1. GET /health            -> 200, status ok, database + s3 substatus ok
#   2. GET /books             -> 200, exactly 12 catalog entries, known titles
#   3. GET /books/1           -> 200, shows "Kokoro"
#   4. GET /covers/1.png      -> 200, image/png
#   5. GET /admin/aws-check   -> all six service pings ok
# -----------------------------------------------------------------------------

set -uo pipefail  # no -e: run every check, count failures, report at the end

BASE_URL="${1:?Usage: smoke-test.sh <BASE_URL>   e.g. smoke-test.sh http://<alb-dns>}"
BASE_URL="${BASE_URL%/}"

FAILURES=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# fetch PATH — sets HTTP_CODE and BODY globals (text endpoints only).
fetch() {
  local path="$1" tmp
  tmp="$(mktemp)"
  HTTP_CODE=$(curl -sS -m 60 -o "$tmp" -w '%{http_code}' \
    "${BASE_URL}${path}" 2>/dev/null) || HTTP_CODE="000"
  BODY="$(cat "$tmp")"
  rm -f "$tmp"
}

# json_get KEY [KEY...] — prints the (nested) value from $BODY, or nothing.
json_get() {
  python3 -c '
import json, sys
try:
    value = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
for key in sys.argv[2:]:
    if not isinstance(value, dict) or key not in value:
        sys.exit(0)
    value = value[key]
print(value)
' "$BODY" "$@"
}

echo "Smoke-testing ${BASE_URL}"
echo ""

# ---- 1. /health ----------------------------------------------------------------
fetch /health
STATUS="$(json_get status)"
DB_CHECK="$(json_get checks database)"
S3_CHECK="$(json_get checks s3)"
if [[ "$HTTP_CODE" == "200" && "$STATUS" == "ok" && "$DB_CHECK" == "ok" && "$S3_CHECK" == "ok" ]]; then
  pass "GET /health -> 200, status=ok (database=ok, s3=ok)"
else
  fail "GET /health -> HTTP $HTTP_CODE, status='${STATUS}', database='${DB_CHECK}', s3='${S3_CHECK}' (body: ${BODY:0:200})"
fi

# ---- 2. /books -------------------------------------------------------------------
fetch /books
BOOK_COUNT=$(grep -o 'data-book-id="' <<<"$BODY" | wc -l | tr -d ' ')
if [[ "$HTTP_CODE" == "200" && "$BOOK_COUNT" == "12" \
      && "$BODY" == *"Kokoro"* && "$BODY" == *"Norwegian Wood"* ]]; then
  pass "GET /books -> 200, 12 titles listed (Kokoro ... Norwegian Wood)"
else
  fail "GET /books -> HTTP $HTTP_CODE, entries=${BOOK_COUNT} (expected 12)"
fi

# ---- 3. /books/1 --------------------------------------------------------------------
fetch /books/1
if [[ "$HTTP_CODE" == "200" && "$BODY" == *"Kokoro"* ]]; then
  pass "GET /books/1 -> 200, detail page shows Kokoro"
else
  fail "GET /books/1 -> HTTP $HTTP_CODE (body: ${BODY:0:120})"
fi

# ---- 4. /covers/1.png -----------------------------------------------------------------
COVER_META=$(curl -sS -m 60 -o /dev/null -w '%{http_code} %{content_type}' \
  "${BASE_URL}/covers/1.png" 2>/dev/null) || COVER_META="000 -"
COVER_CODE="${COVER_META%% *}"
COVER_TYPE="${COVER_META#* }"
if [[ "$COVER_CODE" == "200" && "$COVER_TYPE" == image/png* ]]; then
  pass "GET /covers/1.png -> 200, image/png streamed from object storage"
else
  fail "GET /covers/1.png -> HTTP ${COVER_CODE}, content-type '${COVER_TYPE}'"
fi

# ---- 5. /admin/aws-check -----------------------------------------------------------------
fetch /admin/aws-check
if [[ "$HTTP_CODE" == "200" ]]; then
  for service in s3 secret_db secret_legacy database cloudwatch sts; do
    RESULT="$(json_get "$service")"
    if [[ "$RESULT" == "ok" ]]; then
      pass "/admin/aws-check ${service} -> ok"
    else
      fail "/admin/aws-check ${service} -> '${RESULT}'"
    fi
  done
else
  fail "GET /admin/aws-check -> HTTP $HTTP_CODE (body: ${BODY:0:200})"
fi

# ---- summary ---------------------------------------------------------------------------------
echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "RESULT: ${FAILURES} check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
