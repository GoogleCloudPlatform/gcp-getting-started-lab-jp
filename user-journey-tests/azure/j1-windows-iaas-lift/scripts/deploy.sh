#!/usr/bin/env bash
# deploy.sh — deploy the azure/j1-windows-iaas-lift test bed (fictional clinic group, wil-*) to Azure.
# -----------------------------------------------------------------------------
# Idempotent: `az group create` is create-or-update, and `az deployment group
# create` runs in Incremental mode, so re-running converges. One caveat — both
# securestring passwords are regenerated on every run, so a re-deploy RESETS the
# Windows local admin password and the Azure SQL administrator password.
#
# Everything lands in ONE resource group (wil-rg) so teardown is a single
# `az group delete`.
#
# Deploy order is entirely ARM's problem: dependsOn in arm/azuredeploy.json
# chains NSGs -> VNets -> peerings -> public IP -> load balancer -> availability
# set -> NICs -> VMs -> CustomScriptExtension, alongside the independent SQL,
# storage and vault branches.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   AUTOTEARDOWN_DATE          YYYY-MM-DD for the AutoTeardown tag
#   AZURE_LOCATION             region for the resource group (no fallback)
# Optional:
#   WIL_APP_VM_SIZE / WIL_EPHEMERAL_VM_SIZE   lab SKU overrides
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- load env + pre-flight subscription guard --------------------------------
ENV_FILE="${HOME}/.azure/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_SUBSCRIPTION_ID, AUTOTEARDOWN_DATE)" >&2
  exit 1
fi
: "${EXPECTED_SUBSCRIPTION_ID:?Set EXPECTED_SUBSCRIPTION_ID in ~/.azure/journeys.env}"
: "${AUTOTEARDOWN_DATE:?Set AUTOTEARDOWN_DATE=YYYY-MM-DD in ~/.azure/journeys.env}"
AZURE_LOCATION="${AZURE_LOCATION:?set AZURE_LOCATION in ~/.azure/journeys.env}"
RESOURCE_GROUP="wil-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
echo "Deploying azure/j1-windows-iaas-lift to subscription $SUBSCRIPTION_ID, location $AZURE_LOCATION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARM_DIR="${SCRIPT_DIR}/../arm"

# ---- resource providers ------------------------------------------------------
# A subscription that has never created these resource types rejects the
# deployment with MissingSubscriptionRegistration. Registering is idempotent.
for ns in Microsoft.Compute Microsoft.Network Microsoft.Storage Microsoft.Sql Microsoft.RecoveryServices; do
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
  if [[ "$state" != "Registered" ]]; then
    echo ">>> Registering resource provider $ns (currently: $state)"
    az provider register --namespace "$ns" --wait
  fi
done

# ---- resource group ----------------------------------------------------------
echo ""
echo ">>> Creating resource group $RESOURCE_GROUP"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --tags \
  "Owner=migration-test" \
  "CostCenter=test-journeys" \
  "AutoTeardown=${AUTOTEARDOWN_DATE}" \
  "Journey=azure/j1-windows-iaas-lift" \
  --output none

# ---- generated secrets -------------------------------------------------------
# Both passwords are generated here and never written to the repo. They go into
# a 0600 temp file rather than the command line so they stay out of the process
# table; ARM records securestring values nowhere in deployment history.
# Azure complexity: >=12 chars for a Windows admin, 3 of 4 character classes,
# and the password must not contain the login name. The random body is base64
# alphanumerics and the Aa1_ suffix guarantees all four classes.
gen_password() {
  printf '%sAa1_' "$(openssl rand -base64 24 | tr -d '/+=')"
}
VM_ADMIN_PASSWORD="$(gen_password)"
SQL_ADMIN_PASSWORD="$(gen_password)"

SECRET_PARAMS="$(mktemp)"
chmod 600 "$SECRET_PARAMS"
trap 'rm -f "$SECRET_PARAMS"' EXIT

cat >"$SECRET_PARAMS" <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "autoTeardownDate": { "value": "${AUTOTEARDOWN_DATE}" },
    "adminPassword": { "value": "${VM_ADMIN_PASSWORD}" },
    "sqlAdminPassword": { "value": "${SQL_ADMIN_PASSWORD}" }
  }
}
JSON

# ---- deployment --------------------------------------------------------------
DEPLOY_NAME="wil-deploy-$(date -u +%Y%m%d-%H%M%S)"
echo ""
echo ">>> Running deployment $DEPLOY_NAME"
echo "    (first run takes ~10-15 minutes — the two Windows VMs and their"
echo "     CustomScriptExtension IIS install dominate)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOY_NAME" \
  --template-file "${ARM_DIR}/azuredeploy.json" \
  --parameters "@${ARM_DIR}/azuredeploy.parameters.json" \
  --parameters "@${SECRET_PARAMS}" \
  ${WIL_APP_VM_SIZE:+--parameters appVmSize="${WIL_APP_VM_SIZE}"} \
  ${WIL_EPHEMERAL_VM_SIZE:+--parameters ephemeralVmSize="${WIL_EPHEMERAL_VM_SIZE}"} \
  --output none

# ---- outputs -----------------------------------------------------------------
BASE_URL=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
  --query properties.outputs.baseUrl.value -o tsv)
SQL_FQDN=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
  --query properties.outputs.sqlServerFqdn.value -o tsv)
STORAGE_NAME=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
  --query properties.outputs.storageAccountName.value -o tsv)

echo ""
echo "============================================================"
echo ">>> azure/j1-windows-iaas-lift deployed to $RESOURCE_GROUP."
echo "BASE_URL=${BASE_URL}"
echo "SQL_FQDN=${SQL_FQDN}"
echo "STORAGE_ACCOUNT=${STORAGE_NAME}"
echo ""
echo "The generated Windows and SQL administrator passwords were not printed"
echo "and are not stored. Re-run this script to rotate them."
echo ""
echo "There is no seed step: IIS and the static status page are installed by the"
echo "CustomScriptExtension at VM provisioning time. Allow a minute or two for"
echo "the load balancer probe to mark both instances healthy, then:"
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo "============================================================"
