#!/usr/bin/env bash
# seed.sh — post three deterministic FAQ conversations into a deployed fac-api.
# -----------------------------------------------------------------------------
# Usage: ./scripts/seed.sh <BASE_URL>          (BASE_URL printed by deploy.sh)
#
# Conversation ids and messages are fixed so the data set is deterministic and
# parity checks can compare stored turns across environments. Re-running seeds
# APPENDS a fresh user/assistant turn pair to each conversation (there is no
# delete API); conversations stay readable, turn counts grow by 2 per run.
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- load env + pre-flight account guard -------------------------------------
ENV_FILE="${HOME}/.aws/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_ACCOUNT_ID)" >&2
  exit 1
fi
: "${EXPECTED_ACCOUNT_ID:?Set EXPECTED_ACCOUNT_ID in ~/.aws/journeys.env}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got $ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID)" >&2
  exit 1
fi

BASE_URL="${1:?Usage: seed.sh <BASE_URL>   e.g. seed.sh http://203.0.113.10:8000}"
BASE_URL="${BASE_URL%/}"

# ---- deterministic seed set ----------------------------------------------------
seed_one() {
  local conversation_id="$1" message="$2"
  local code
  code=$(curl -sS -m 30 -o /dev/null -w '%{http_code}' \
    -X POST "${BASE_URL}/chat" \
    -H 'Content-Type: application/json' \
    -d "{\"conversation_id\": \"${conversation_id}\", \"message\": \"${message}\"}") || code="000"
  if [[ "$code" != "200" ]]; then
    echo "FATAL: POST /chat for ${conversation_id} returned HTTP ${code}" >&2
    exit 1
  fi
  echo "seeded ${conversation_id}: ${message}"
}

seed_one "fac-seed-001" "How do I reset my password?"
seed_one "fac-seed-002" "What are your support desk hours?"
seed_one "fac-seed-003" "How do I change my billing plan?"

echo ""
echo "Done. Inspect with: curl -s ${BASE_URL}/conversations/fac-seed-001"
