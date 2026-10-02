#!/usr/bin/env bash
# seed.sh — post three deterministic bookings into a deployed booking-api.
# -----------------------------------------------------------------------------
# Usage: ./scripts/seed.sh <BASE_URL>       (BASE_URL printed by deploy.sh)
#        ./scripts/seed.sh                  (prompts for BASE_URL)
#
# The (item_id, days) set is fixed so the data is deterministic and parity
# checks can recompute the same totals across environments. booking_id values
# are server-generated UUIDs; re-running APPENDS three fresh bookings (there
# is no delete API).
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

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  read -r -p "BASE_URL (printed by deploy.sh): " BASE_URL
fi
[[ -n "$BASE_URL" ]] || { echo "FATAL: BASE_URL is required" >&2; exit 1; }
BASE_URL="${BASE_URL%/}"

# ---- deterministic seed set ----------------------------------------------------
seed_one() {
  local item_id="$1" days="$2" body tmp code
  tmp="$(mktemp)"
  code=$(curl -sS -m 30 -o "$tmp" -w '%{http_code}' \
    -X POST "${BASE_URL}/bookings" \
    -H 'Content-Type: application/json' \
    -d "{\"item_id\": ${item_id}, \"days\": ${days}}") || code="000"
  body="$(cat "$tmp")"
  rm -f "$tmp"

  if [[ "$code" != "201" ]]; then
    echo "FATAL: POST /bookings item_id=${item_id} days=${days} -> HTTP ${code}: ${body:0:200}" >&2
    exit 1
  fi
  echo "seeded: item_id=${item_id} days=${days} -> ${body:0:160}"
}

echo "Seeding ${BASE_URL} with 3 deterministic bookings..."
seed_one 1 2
seed_one 2 5
seed_one 3 1
echo "Done."
