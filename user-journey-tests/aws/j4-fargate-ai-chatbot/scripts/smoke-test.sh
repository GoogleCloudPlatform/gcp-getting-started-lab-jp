#!/usr/bin/env bash
# smoke-test.sh — end-to-end verification of a deployed fac-api.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#
# Prints one "PASS: ..." / "FAIL: ..." line per check and exits non-zero if
# ANY check fails. Deliberately cloud-agnostic: it only speaks HTTP to the
# service's public endpoint, so the same script verifies the current
# deployment AND any future re-platformed one. Requires curl + python3.
#
# Checks:
#   1. GET  /health                        -> 200, status == "ok"
#   2. POST /chat (fresh conversation)     -> 200, non-empty reply, llm_mode set
#   3. GET  /conversations/<id>            -> 200, exactly 2 turns
#   4. POST /conversations/<id>/archive    -> 200, object_key returned
#   5. GET  /admin/aws-check               -> s3/dynamodb/bedrock/sts all "ok"
# -----------------------------------------------------------------------------

set -uo pipefail  # no -e: run every check, count failures, report at the end

BASE_URL="${1:?Usage: smoke-test.sh <BASE_URL>   e.g. smoke-test.sh http://203.0.113.10:8000}"
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

# ---- 1. /health ----------------------------------------------------------------
fetch GET /health
STATUS="$(json_get status)"
if [[ "$HTTP_CODE" == "200" && "$STATUS" == "ok" ]]; then
  pass "GET /health -> 200, status=ok"
else
  fail "GET /health -> HTTP $HTTP_CODE, status='${STATUS}' (body: ${BODY:0:200})"
fi

# ---- 2. /chat (fresh conversation) ----------------------------------------------
CID="smoke-$(date +%s)"
fetch POST /chat "{\"conversation_id\": \"${CID}\", \"message\": \"How do I reset my password?\"}"
REPLY="$(json_get reply)"
LLM_MODE="$(json_get llm_mode)"
if [[ "$HTTP_CODE" == "200" && -n "$REPLY" && -n "$LLM_MODE" ]]; then
  pass "POST /chat -> 200, non-empty reply (llm_mode=${LLM_MODE})"
else
  fail "POST /chat -> HTTP $HTTP_CODE, reply='${REPLY:0:80}', llm_mode='${LLM_MODE}'"
fi

# ---- 3. /conversations/<id> ------------------------------------------------------
fetch GET "/conversations/${CID}"
TURNS="$(json_len turns)"
if [[ "$HTTP_CODE" == "200" && "$TURNS" == "2" ]]; then
  pass "GET /conversations/${CID} -> 200, 2 turns (user + assistant)"
else
  fail "GET /conversations/${CID} -> HTTP $HTTP_CODE, turns=${TURNS:-none}"
fi

# ---- 4. archive -------------------------------------------------------------------
fetch POST "/conversations/${CID}/archive"
OBJECT_KEY="$(json_get object_key)"
if [[ "$HTTP_CODE" == "200" && -n "$OBJECT_KEY" ]]; then
  pass "POST /conversations/${CID}/archive -> 200, object_key=${OBJECT_KEY}"
else
  fail "POST /conversations/${CID}/archive -> HTTP $HTTP_CODE (body: ${BODY:0:200})"
fi

# ---- 5. /admin/aws-check ----------------------------------------------------------
fetch GET /admin/aws-check
if [[ "$HTTP_CODE" == "200" ]]; then
  for service in s3 dynamodb bedrock sts; do
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

# ---- summary ------------------------------------------------------------------------
echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "RESULT: ${FAILURES} check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
