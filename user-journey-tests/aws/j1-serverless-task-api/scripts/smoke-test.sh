#!/usr/bin/env bash
# smoke-test.sh BASE_URL — end-to-end checks against a live task-reminder deployment.
# The SAME script must pass against the AWS deployment and any migrated one.
set -uo pipefail

BASE_URL="${1:?Usage: smoke-test.sh BASE_URL}"
BASE_URL="${BASE_URL%/}"
FAILURES=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# 1. health
code=$(curl -s -o /tmp/sta-health.json -w '%{http_code}' "${BASE_URL}/health")
if [[ "$code" == "200" ]]; then pass "/health returns 200"; else fail "/health returned ${code}"; fi

# 2. create
resp=$(curl -s -X POST "${BASE_URL}/tasks" -H 'content-type: application/json' \
  -d '{"title":"smoke-test task","due_at":"2030-01-01T00:00:00Z"}')
task_id=$(echo "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
if [[ -n "$task_id" ]]; then pass "POST /tasks created ${task_id:0:8}…"; else fail "POST /tasks gave no id: ${resp:0:120}"; fi

# 3. list contains it
listed=$(curl -s "${BASE_URL}/tasks" | python3 -c "import json,sys; d=json.load(sys.stdin); print(any(t.get('id')=='${task_id}' for t in d.get('tasks',[])))" 2>/dev/null)
if [[ "$listed" == "True" ]]; then pass "GET /tasks lists the new task"; else fail "new task missing from GET /tasks"; fi

# 4. complete it
status=$(curl -s -X POST "${BASE_URL}/tasks/${task_id}/complete" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null)
if [[ "$status" == "done" ]]; then pass "POST /tasks/{id}/complete -> done"; else fail "complete returned status='${status}'"; fi

# 5. dependency dashboard
overall=$(curl -s "${BASE_URL}/admin/aws-check" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("overall",""))' 2>/dev/null)
if [[ "$overall" == "ok" ]]; then pass "/admin/aws-check overall ok"; else fail "/admin/aws-check overall='${overall}'"; fi

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "SMOKE TEST PASSED (5/5) against ${BASE_URL}"
  exit 0
fi
echo "SMOKE TEST FAILED (${FAILURES} failing) against ${BASE_URL}"
exit 1
