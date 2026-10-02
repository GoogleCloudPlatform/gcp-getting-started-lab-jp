#!/usr/bin/env bash
# 05-verify.sh — agent-contract verification of the deployed copilot.
#
# The journey's HTTP smoke test exercises the FastAPI wrapper this migration
# retires, so parity is asserted at the agent contract instead — same tools,
# same corpus, plus what the platform took over (managed sessions) and what
# the model gained (a live retrieval loop instead of the pipeline).
#
# Checks (PASS/FAIL per line, non-zero exit on any failure):
#   1. per-diem question -> search_kb called, answer cites EXP-100 and 65 USD
#   2. honest no-match   -> nonsense yields no fabricated [XXX-000] citation
#   3. session continuity -> a pronoun follow-up resolves from turn 1
#   4. managed sessions   -> the session appears in the platform sessions API

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/00-env.sh"

ENGINE="$(copilot_engine)"
[[ -n "$ENGINE" ]] || { echo "FATAL: no ${PROJECT_NAME} engine found" >&2; exit 1; }
echo "Engine: ${ENGINE}"
TOKEN="$(gcloud auth print-access-token)"
URL="https://${REGION}-aiplatform.googleapis.com/v1/${ENGINE}"

FAILED=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=$((FAILED + 1)); }

# converse MESSAGE [SESSION] -> "TOOLS<TAB>TEXT"
converse() {
  local message="$1" session="${2:-}"
  local input
  input="{\"user_id\": \"policy-desk\", \"message\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$message")"
  [[ -n "$session" ]] && input+=", \"session_id\": \"$session\""
  input+="}"
  curl -sS -m 180 -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
    "${URL}:streamQuery" -d "{\"class_method\": \"async_stream_query\", \"input\": ${input}}" \
    | python3 -c "
import json, sys
tools, text = [], []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    event = json.loads(line)
    for part in event.get('content', {}).get('parts', []):
        if part.get('function_call'):
            tools.append(part['function_call']['name'])
        if part.get('text'):
            text.append(part['text'])
print(','.join(tools) + '\t' + ' '.join(text).replace('\n', ' '))"
}

# ---- 1 ---------------------------------------------------------------------------
OUT="$(converse 'What is the per-diem for domestic travel?')"
TOOLS="${OUT%%$'\t'*}"; TEXT="${OUT#*$'\t'}"
if [[ "$TOOLS" == *search_kb* && "$TEXT" == *EXP-100* && "$TEXT" == *65* ]]; then
  pass "per-diem -> search_kb ran, cited EXP-100, 65 USD"
else
  fail "per-diem -> tools='${TOOLS}', text='${TEXT:0:140}'"
fi

# ---- 2 ---------------------------------------------------------------------------
OUT="$(converse 'zzz qqq xyzzy')"
TEXT="${OUT#*$'\t'}"
if python3 -c "import re,sys; sys.exit(0 if not re.search(r'\[[A-Z]{3}-\d{3}', sys.argv[1]) else 1)" "$TEXT"; then
  pass "nonsense -> no fabricated citation"
else
  fail "nonsense -> fabricated citation in '${TEXT:0:140}'"
fi

# ---- 3 ---------------------------------------------------------------------------
SESSION="$(curl -sS -m 60 -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  "${URL}:query" -d '{"class_method": "async_create_session", "input": {"user_id": "policy-desk"}}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['output']['id'])")"
converse "Look up the data retention schedule RET-600 and summarize it." "$SESSION" >/dev/null
OUT="$(converse 'Which team owns that document?' "$SESSION")"
TEXT="${OUT#*$'\t'}"
if [[ "$TEXT" == *Legal* ]]; then
  pass "continuity -> pronoun resolved to RET-600 (owner Legal) in session ${SESSION}"
else
  fail "continuity -> text='${TEXT:0:160}'"
fi

# ---- 4 ---------------------------------------------------------------------------
LISTED="$(curl -sS -m 60 -H "Authorization: Bearer ${TOKEN}" "${URL}/sessions" | python3 -c "
import json, sys
ids = [s['name'].rsplit('/', 1)[-1] for s in json.load(sys.stdin).get('sessions', [])]
print('yes' if '${SESSION}' in ids else 'no')")"
[[ "$LISTED" == "yes" ]] \
  && pass "managed sessions -> ${SESSION} listed by the platform API" \
  || fail "managed sessions -> ${SESSION} missing from the platform list"

echo ""
if [[ "$FAILED" -gt 0 ]]; then
  echo "RESULT: ${FAILED} check(s) FAILED"
  exit 1
fi
echo "RESULT: all checks passed"
