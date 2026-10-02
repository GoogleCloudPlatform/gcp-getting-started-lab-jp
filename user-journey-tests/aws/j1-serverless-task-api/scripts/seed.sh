#!/usr/bin/env bash
# seed.sh — create 5 deterministic tasks through the live API.
# Usage: seed.sh [BASE_URL]   (defaults to the terraform output)
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${1:-$(terraform -chdir="${SCRIPT_DIR}/../terraform" output -raw api_endpoint)}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got ${ACCOUNT_ID}, expected ${EXPECTED_ACCOUNT_ID})" >&2
  exit 1
fi

titles=(
  "Renew ALB TLS cert"
  "Rotate on-call schedule"
  "Prep quarterly infra review"
  "Archive 2025 exports"
  "Update runbook links"
)

for i in "${!titles[@]}"; do
  due=$(date -u -d "+$((i + 1)) day" +%Y-%m-%dT09:00:00Z 2>/dev/null || date -u +%Y-%m-%dT09:00:00Z)
  curl -sf -X POST "${BASE_URL}/tasks" \
    -H 'content-type: application/json' \
    -d "{\"title\":\"${titles[$i]}\",\"due_at\":\"${due}\"}" >/dev/null
  echo "seeded: ${titles[$i]}"
done
echo "Seed complete (5 tasks)."
