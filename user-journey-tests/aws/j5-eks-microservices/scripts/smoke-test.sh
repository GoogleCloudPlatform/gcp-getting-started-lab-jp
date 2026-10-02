#!/usr/bin/env bash
# smoke-test.sh — end-to-end verification of a deployed equipment-marketplace stack (fictional).
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#
# Prints one "PASS: ..." / "FAIL: ..." line per check and exits non-zero if
# ANY check fails. Deliberately cloud-agnostic: it only speaks HTTP to the
# public edge (every route, including the catalog, is served through
# booking-api's gateway), so the same script verifies the current deployment
# AND any future re-platformed one. Requires curl + python3.
#
# Checks:
#   1. GET  /health              -> 200, status == "ok"
#   2. GET  /catalog             -> 200, exactly 12 items
#   3. GET  /catalog/3           -> 200, expected deterministic name
#   4. POST /bookings            -> 201, booking_id, status confirmed,
#                                   deterministic total_jpy
#   5. GET  /bookings/<id>       -> 200, round-trips the stored booking
#   6. GET  /admin/aws-check     -> overall ok (dynamodb + sts subchecks ok)
# -----------------------------------------------------------------------------

set -uo pipefail # no -e: run every check, count failures, report at the end

BASE_URL="${1:?Usage: smoke-test.sh <BASE_URL>   e.g. smoke-test.sh http://ems-nlb.example:80}"
BASE_URL="${BASE_URL%/}"

FAILURES=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# fetch METHOD PATH [JSON_BODY] — sets HTTP_CODE and BODY globals.
fetch() {
  local method="$1" path="$2" data="${3:-}" tmp
  tmp="$(mktemp)"
  if [[ -n "$data" ]]; then
    HTTP_CODE=$(curl -sS -m 60 -o "$tmp" -w '%{http_code}' \
      -X "$method" -H 'Content-Type: application/json' -d "$data" \
      "${BASE_URL}${path}" 2>/dev/null) || HTTP_CODE="000"
  else
    HTTP_CODE=$(curl -sS -m 60 -o "$tmp" -w '%{http_code}' \
      -X "$method" "${BASE_URL}${path}" 2>/dev/null) || HTTP_CODE="000"
  fi
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

# json_len KEY — prints len(body[KEY]) if it is a list, or nothing.
json_len() {
  python3 -c '
import json, sys
try:
    value = json.loads(sys.argv[1]).get(sys.argv[2])
except Exception:
    sys.exit(0)
if isinstance(value, list):
    print(len(value))
' "$BODY" "$1"
}

echo "Smoke-testing ${BASE_URL}"
echo ""

# ---- 1. /health (retries connection failures: fresh LBs take a few minutes) -----
ATTEMPTS=0
while :; do
  fetch GET /health
  ATTEMPTS=$((ATTEMPTS + 1))
  [[ "$HTTP_CODE" != "000" || "$ATTEMPTS" -ge 18 ]] && break
  echo "  (edge not answering yet, retry ${ATTEMPTS}/18 in 10s...)"
  sleep 10
done
STATUS="$(json_get status)"
if [[ "$HTTP_CODE" == "200" && "$STATUS" == "ok" ]]; then
  pass "GET /health -> 200, status=ok"
else
  fail "GET /health -> HTTP $HTTP_CODE, status='${STATUS}' (body: ${BODY:0:200})"
fi

# ---- 2. /catalog ------------------------------------------------------------------
fetch GET /catalog
ITEM_COUNT="$(json_len items)"
if [[ "$HTTP_CODE" == "200" && "$ITEM_COUNT" == "12" ]]; then
  pass "GET /catalog -> 200, 12 items"
else
  fail "GET /catalog -> HTTP $HTTP_CODE, items=${ITEM_COUNT:-none}"
fi

# ---- 3. /catalog/3 (deterministic seed inventory) -----------------------------------
fetch GET /catalog/3
NAME="$(json_get name)"
if [[ "$HTTP_CODE" == "200" && "$NAME" == "Portable LTE Wi-Fi Router" ]]; then
  pass "GET /catalog/3 -> 200, name='${NAME}'"
else
  fail "GET /catalog/3 -> HTTP $HTTP_CODE, name='${NAME}'"
fi

# ---- 4. POST /bookings (item 7 @ 1200 JPY/day x 3 days = 3600) ----------------------
fetch POST /bookings '{"item_id": 7, "days": 3}'
BOOKING_ID="$(json_get booking_id)"
BSTATUS="$(json_get status)"
TOTAL="$(json_get total_jpy)"
if [[ "$HTTP_CODE" == "201" && -n "$BOOKING_ID" && "$BSTATUS" == "confirmed" && "$TOTAL" == "3600" ]]; then
  pass "POST /bookings -> 201, status=confirmed, total_jpy=3600"
else
  fail "POST /bookings -> HTTP $HTTP_CODE, booking_id='${BOOKING_ID}', status='${BSTATUS}', total_jpy='${TOTAL}'"
fi

# ---- 5. GET /bookings/<id> (round-trip through persistence) --------------------------
if [[ -n "$BOOKING_ID" ]]; then
  fetch GET "/bookings/${BOOKING_ID}"
  RSTATUS="$(json_get status)"
  RITEM="$(json_get item_id)"
  if [[ "$HTTP_CODE" == "200" && "$RSTATUS" == "confirmed" && "$RITEM" == "7" ]]; then
    pass "GET /bookings/${BOOKING_ID:0:8}... -> 200, stored booking round-trips"
  else
    fail "GET /bookings/${BOOKING_ID} -> HTTP $HTTP_CODE, status='${RSTATUS}', item_id='${RITEM}'"
  fi
else
  fail "GET /bookings/<id> skipped: no booking_id from check 4"
fi

# ---- 6. /admin/aws-check --------------------------------------------------------------
fetch GET /admin/aws-check
OVERALL="$(json_get overall)"
if [[ "$HTTP_CODE" == "200" && "$OVERALL" == "ok" ]]; then
  pass "GET /admin/aws-check -> 200, overall=ok"
else
  fail "GET /admin/aws-check -> HTTP $HTTP_CODE, overall='${OVERALL}' (body: ${BODY:0:200})"
fi
for service in dynamodb sts; do
  RESULT="$(json_get checks "$service")"
  if [[ "$RESULT" == "ok" ]]; then
    pass "/admin/aws-check ${service} -> ok"
  else
    fail "/admin/aws-check ${service} -> '${RESULT}'"
  fi
done

# ---- summary ----------------------------------------------------------------------------
echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "RESULT: ${FAILURES} check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
