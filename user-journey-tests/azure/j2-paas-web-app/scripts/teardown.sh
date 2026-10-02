#!/usr/bin/env bash
# teardown.sh — destroy the azure/j2-paas-web-app test bed.
# -----------------------------------------------------------------------------
# The whole shop lives in one resource group, so teardown is a single
# `az group delete`. It DELETES rather than stops: a stopped App Service plan
# still bills, and a stopped flexible server still holds its storage.
#
# One thing outlives the resource group. Key Vault soft delete cannot be turned
# off, so the vault lingers for its retention window and blocks a re-deploy that
# computes the same vault name. This script purges it.
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
RESOURCE_GROUP="pwa-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi

if ! az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "Resource group $RESOURCE_GROUP does not exist in subscription $SUBSCRIPTION_ID — nothing to do."
  exit 0
fi

# Captured before the delete, because afterwards there is nothing left to ask.
# The purge below is addressed by region, and the vault's own record is the only
# trustworthy source for that — no region is hard-coded in this repository.
KEY_VAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")
KEY_VAULT_LOCATION=$(az keyvault list --resource-group "$RESOURCE_GROUP" \
  --query "[0].location" -o tsv 2>/dev/null || echo "")

# ---- confirmation ------------------------------------------------------------
echo "About to DELETE resource group ${RESOURCE_GROUP} in subscription ${SUBSCRIPTION_ID}."
echo "Everything in azure/j2-paas-web-app goes with it:"
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

# ---- purge the soft-deleted vault --------------------------------------------
if [[ -n "$KEY_VAULT_NAME" && -n "$KEY_VAULT_LOCATION" ]]; then
  echo ">>> Purging soft-deleted key vault ${KEY_VAULT_NAME} (${KEY_VAULT_LOCATION})"
  if az keyvault purge --name "$KEY_VAULT_NAME" --location "$KEY_VAULT_LOCATION" --output none 2>/dev/null; then
    echo "    purged."
  else
    echo "    could not purge ${KEY_VAULT_NAME} — it may already be gone, or the" >&2
    echo "    signed-in principal may lack Microsoft.KeyVault/locations/deletedVaults/purge/action." >&2
    echo "    A re-deploy into the same resource group will fail until it is purged." >&2
  fi
fi

echo ""
echo "============================================================"
echo ">>> azure/j2-paas-web-app torn down. ${RESOURCE_GROUP} is gone."
echo "Confirm nothing survived subscription-wide:"
echo "  az resource list --tag Journey=azure/j2-paas-web-app -o table"
echo "  az keyvault list-deleted --query \"[?name=='${KEY_VAULT_NAME}']\" -o table"
echo "============================================================"
