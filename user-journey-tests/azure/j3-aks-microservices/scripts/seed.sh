#!/usr/bin/env bash
# seed.sh — post three fixed parcels into a deployed tracking-api.
# -----------------------------------------------------------------------------
# Usage: ./scripts/seed.sh <BASE_URL>       (BASE_URL printed by deploy.sh)
#        ./scripts/seed.sh                  (prompts for BASE_URL)
#
# The three parcels are always the same, so a parity check can compare the
# stored documents between two deployments. Re-running overwrites them rather
# than adding more: the parcel id is the document id.
#
# Each POST also puts one scan event on the queue, keyed by parcel id, so
# seeding exercises the notifier as well as the write path.
# -----------------------------------------------------------------------------

set -euo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  read -r -p "BASE_URL (printed by deploy.sh): " BASE_URL
fi
[[ -n "$BASE_URL" ]] || {
  echo "FATAL: BASE_URL is required" >&2
  exit 1
}
BASE_URL="${BASE_URL%/}"

seed_one() {
  local parcel_id="$1" origin="$2" destination="$3" body tmp code
  tmp="$(mktemp)"
  code=$(curl -sS -m 30 -o "$tmp" -w '%{http_code}' \
    -X POST "${BASE_URL}/parcels" \
    -H 'Content-Type: application/json' \
    -d "{\"parcelId\": \"${parcel_id}\", \"origin\": \"${origin}\", \"destination\": \"${destination}\"}") || code="000"
  body="$(cat "$tmp")"
  rm -f "$tmp"

  if [[ "$code" != "201" ]]; then
    echo "FATAL: POST /parcels ${parcel_id} -> HTTP ${code}: ${body:0:200}" >&2
    exit 1
  fi
  echo "seeded: ${parcel_id} ${origin} -> ${destination}"
}

echo "Seeding ${BASE_URL} with 3 parcels..."
seed_one "AKM-100001" "Adachi" "Yokohama"
seed_one "AKM-100002" "Adachi" "Kawaguchi"
seed_one "AKM-100003" "Funabashi" "Chiba"
echo "Done."
