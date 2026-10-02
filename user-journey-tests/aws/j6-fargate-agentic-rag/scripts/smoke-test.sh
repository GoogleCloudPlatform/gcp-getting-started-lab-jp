#!/usr/bin/env bash
# smoke-test.sh — end-to-end verification of a deployed policy copilot.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#
# Speaks only HTTP, so the identical script verifies this deployment and any
# future re-platformed one. Prints PASS/FAIL per check; non-zero exit if any
# check fails. Requires curl + python3.
#
# Checks:
#   1. /healthz                    -> 200, answer_mode present
#   2. /diagnostics                -> identity/conversations/knowledge_base/credentials all "pass"
#   3. /kb/topics                  -> 200, >= 6 topics
#   4. /ask (direct question)      -> cited answer from EXP-100, retrieval steps recorded
#   5. /ask (vague question)       -> the retrieval loop RETRIES: 2 search steps (pipeline mode)
#   6. /ask (follow-up, same conversation) -> conversation id preserved
#   7. /conversations/{id}         -> >= 4 stored turns
#   8. /kb/documents/EXP-100       -> 200 with title + sections
# -----------------------------------------------------------------------------

set -uo pipefail # no -e: run every check, count failures

BASE="${1:?Usage: smoke-test.sh <BASE_URL>}"
BASE="${BASE%/}"

FAILED=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=$((FAILED + 1)); }

# http METHOD PATH [JSON] -> sets CODE and BODY
http() {
  local method="$1" path="$2" data="${3:-}" tmp
  tmp="$(mktemp)"
  if [[ -n "$data" ]]; then
    CODE=$(curl -sS -m 60 -o "$tmp" -w '%{http_code}' -X "$method" \
      -H 'Content-Type: application/json' -d "$data" "${BASE}${path}" 2>/dev/null) || CODE=000
  else
    CODE=$(curl -sS -m 60 -o "$tmp" -w '%{http_code}' -X "$method" "${BASE}${path}" 2>/dev/null) || CODE=000
  fi
  BODY="$(cat "$tmp")"; rm -f "$tmp"
}

# jget PYEXPR — evaluate against the parsed BODY as `d`
jget() {
  python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
try:
    print(eval(sys.argv[2]))
except Exception:
    pass
' "$BODY" "$1"
}

echo "Smoke-testing ${BASE}"
echo ""

# 1 -------------------------------------------------------------------------------
http GET /healthz
MODE=$(jget 'd["answer_mode"]')
[[ "$CODE" == 200 && -n "$MODE" ]] \
  && pass "/healthz -> 200, answer_mode=${MODE}" \
  || fail "/healthz -> HTTP $CODE (${BODY:0:120})"

# 2 -------------------------------------------------------------------------------
http GET /diagnostics
if [[ "$CODE" == 200 ]]; then
  for dep in identity conversations knowledge_base credentials; do
    STATE=$(jget "d['${dep}']")
    [[ "$STATE" == "pass" ]] && pass "/diagnostics ${dep} -> pass" \
                             || fail "/diagnostics ${dep} -> '${STATE}'"
  done
else
  fail "/diagnostics -> HTTP $CODE"
fi

# 3 -------------------------------------------------------------------------------
http GET /kb/topics
TOPICS=$(jget 'len(d["topics"])')
[[ "$CODE" == 200 && "${TOPICS:-0}" -ge 6 ]] \
  && pass "/kb/topics -> ${TOPICS} topics" \
  || fail "/kb/topics -> HTTP $CODE, topics='${TOPICS}'"

# 4 -------------------------------------------------------------------------------
http POST /ask '{"question": "What is the per-diem for domestic travel?"}'
CONV=$(jget 'd["conversation_id"]')
ANSWER=$(jget 'd["answer"][:60]')
SRC=$(jget '",".join(d["sources"])')
STEPS=$(jget 'len(d["steps"])')
if [[ "$CODE" == 200 && -n "$ANSWER" && "$SRC" == *EXP-100* && "${STEPS:-0}" -ge 2 ]]; then
  pass "/ask direct -> cited ${SRC} in ${STEPS} steps (conversation ${CONV})"
else
  fail "/ask direct -> HTTP $CODE, sources='${SRC}', steps='${STEPS}'"
fi

# 5 -------------------------------------------------------------------------------
# The agentic differentiator: a vague question must make the copilot judge
# the first result set and search AGAIN. Deterministic in pipeline mode.
http POST /ask '{"question": "what about laptops when someone leaves"}'
SEARCHES=$(jget 'sum(1 for s in d["steps"] if s["action"] == "search_kb")')
SRC5=$(jget '",".join(d["sources"])')
WANT=2; [[ "$MODE" == "model" ]] && WANT=1 # live model may nail it first try
if [[ "$CODE" == 200 && "${SEARCHES:-0}" -ge "$WANT" && -n "$SRC5" ]]; then
  pass "/ask vague -> ${SEARCHES} search passes, cited ${SRC5}"
else
  fail "/ask vague -> HTTP $CODE, searches='${SEARCHES}' (want >= ${WANT}), sources='${SRC5}'"
fi

# 6 -------------------------------------------------------------------------------
http POST /ask "{\"question\": \"and who approves claims over 500 dollars?\", \"conversation_id\": \"${CONV}\"}"
CONV2=$(jget 'd["conversation_id"]')
[[ "$CODE" == 200 && "$CONV2" == "$CONV" ]] \
  && pass "/ask follow-up -> conversation ${CONV} preserved" \
  || fail "/ask follow-up -> HTTP $CODE, conversation '${CONV2}' (sent '${CONV}')"

# 7 -------------------------------------------------------------------------------
http GET "/conversations/${CONV}"
TURNS=$(jget 'd["turn_count"]')
[[ "$CODE" == 200 && "${TURNS:-0}" -ge 4 ]] \
  && pass "/conversations -> ${TURNS} turns stored" \
  || fail "/conversations -> HTTP $CODE, turns='${TURNS}'"

# 8 -------------------------------------------------------------------------------
http GET /kb/documents/EXP-100
TITLE=$(jget 'd["title"]')
SECTIONS=$(jget 'len(d["sections"])')
[[ "$CODE" == 200 && -n "$TITLE" && "${SECTIONS:-0}" -ge 2 ]] \
  && pass "/kb/documents/EXP-100 -> '${TITLE}' (${SECTIONS} sections)" \
  || fail "/kb/documents/EXP-100 -> HTTP $CODE"

echo ""
if [[ "$FAILED" -gt 0 ]]; then
  echo "RESULT: ${FAILED} check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
