#!/usr/bin/env bash
# seed.sh — put a working day's claims through the pipeline.
# -----------------------------------------------------------------------------
# Uploads five claim documents named to the branch scanners' contract:
#
#   <claim-ref>_<branch>_<amount-in-yen>.pdf
#
# Four sit under the escalation threshold and settle at the adjuster desk. One
# (DFP-2026-0404, west region, 1,250,000 JPY) is over it, so the approval chain runs
# and writes its own rows — which is the only way the claim state table ends up
# holding the approval trail the compliance response promised.
#
# Idempotent: the file names are fixed, blob upload overwrites, and the claim
# state rows are upserted on the same keys.
#
# Confirmation is not needed — this only writes claim documents.
# -----------------------------------------------------------------------------

set -euo pipefail

ENV_FILE="${HOME}/.azure/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
: "${EXPECTED_SUBSCRIPTION_ID:?Set EXPECTED_SUBSCRIPTION_ID in ~/.azure/journeys.env}"
RESOURCE_GROUP="dfp-rg"
INTAKE_CONTAINER="intake"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi

STORAGE_ACCOUNT=$(az storage account list --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'dfpclaims')].name | [0]" -o tsv)
if [[ -z "$STORAGE_ACCOUNT" ]]; then
  echo "FATAL: no claims storage account in ${RESOURCE_GROUP} — run ./scripts/deploy.sh first" >&2
  exit 1
fi

# The key is read into the environment rather than onto a command line, so it
# never reaches the process table and is never printed.
export AZURE_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
AZURE_STORAGE_KEY=$(az storage account keys list --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" --query "[0].value" -o tsv)
export AZURE_STORAGE_KEY

CLAIMS=(
  "DFP-2026-0401_EAST_84000.pdf"
  "DFP-2026-0402_EAST_212500.pdf"
  "DFP-2026-0403_NORTH_46800.pdf"
  "DFP-2026-0404_WEST_1250000.pdf"
  "DFP-2026-0405_SOUTH_318000.pdf"
)

WORK_DIR="${TMPDIR:-/tmp}/dfp-seed-$$"
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

echo ">>> Seeding ${#CLAIMS[@]} claim documents into ${STORAGE_ACCOUNT}/${INTAKE_CONTAINER}"
for claim_file in "${CLAIMS[@]}"; do
  printf '%%PDF-1.4 scanned claim %s\n' "${claim_file%%_*}" >"${WORK_DIR}/${claim_file}"
  az storage blob upload \
    --container-name "$INTAKE_CONTAINER" \
    --name "$claim_file" \
    --file "${WORK_DIR}/${claim_file}" \
    --overwrite --only-show-errors --output none
  echo "    ${claim_file}"
done

echo ""
echo "Seeded. Event Grid delivery plus the two hops through the pipeline take"
echo "under a minute; the approval chain on DFP-2026-0404 adds a few seconds."
echo "Read the results back with:"
echo "  az storage entity query --account-name ${STORAGE_ACCOUNT} --table-name claimstate --output table"
