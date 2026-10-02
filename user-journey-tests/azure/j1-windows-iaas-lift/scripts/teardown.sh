#!/usr/bin/env bash
# teardown.sh — destroy the azure/j1-windows-iaas-lift test bed.
# -----------------------------------------------------------------------------
# The whole estate lives in one resource group, so teardown is a single
# `az group delete`. It DELETES rather than deallocates: a deallocated VM stops
# compute billing but still consumes regional vCPU quota.
#
# Confirmation-gated: type "yes" at the prompt, or set FORCE_TEARDOWN=1.
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- load env + pre-flight subscription guard --------------------------------
ENV_FILE="${HOME}/.azure/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
: "${EXPECTED_SUBSCRIPTION_ID:?Set EXPECTED_SUBSCRIPTION_ID in ~/.azure/journeys.env}"
RESOURCE_GROUP="wil-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi

if ! az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "Resource group $RESOURCE_GROUP does not exist in subscription $SUBSCRIPTION_ID — nothing to do."
  exit 0
fi

# ---- confirmation ------------------------------------------------------------
echo "About to DELETE resource group ${RESOURCE_GROUP} in subscription ${SUBSCRIPTION_ID}."
echo "Everything in azure/j1-windows-iaas-lift goes with it:"
az resource list --resource-group "$RESOURCE_GROUP" \
  --query "[].{name:name, type:type}" -o table || true
echo ""

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p 'Type "yes" to confirm: ' CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted — nothing was deleted."
    exit 1
  fi
fi

# ---- delete ------------------------------------------------------------------
echo ""
echo ">>> Deleting resource group ${RESOURCE_GROUP} (this takes several minutes)"
az group delete --name "$RESOURCE_GROUP" --yes

# ---- verify ------------------------------------------------------------------
if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "FATAL: ${RESOURCE_GROUP} still exists after delete — investigate before re-running." >&2
  exit 1
fi

echo ""
echo "============================================================"
echo ">>> azure/j1-windows-iaas-lift torn down. ${RESOURCE_GROUP} is gone."
echo "Confirm nothing survived subscription-wide:"
echo "  az resource list --tag Journey=azure/j1-windows-iaas-lift -o table"
echo "============================================================"
