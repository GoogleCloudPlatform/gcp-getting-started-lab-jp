#!/usr/bin/env bash
# deploy.sh — deploy the azure/j2-paas-web-app test bed (the stationery shop, pwa-*) to Azure.
# -----------------------------------------------------------------------------
# Idempotent: `az group create` is create-or-update and `az deployment group
# create` runs in Incremental mode, so re-running converges. One caveat — the
# PostgreSQL administrator password and the Django SECRET_KEY are regenerated on
# every run, so a re-deploy ROTATES both. Neither is ever written to this
# repository or printed to the terminal.
#
# Everything lands in ONE resource group (pwa-rg) so teardown is a single
# `az group delete`.
#
# Deploy order is expressed through Bicep module inputs in bicep/main.bicep:
# storage, key vault and monitoring first, then the database, then the web app
# and its staging slot, then the role assignments for the web app's identity,
# then Front Door in front of the site. The application itself is pushed
# afterwards as a zip and built on the server by Oryx.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   AUTOTEARDOWN_DATE          YYYY-MM-DD for the AutoTeardown tag
#   AZURE_LOCATION             region for the resource group and everything in
#                              it — no region is hard-coded in this repository
# Optional per-run overrides, for a subscription whose catalogue does not carry
# the template defaults (S1 / Standard_B1ms):
#   PWA_APP_PLAN_SKU_NAME      App Service plan SKU, e.g. P0v3 (slots need
#   PWA_APP_PLAN_SKU_TIER      Standard or better, so a B-series will not do)
#   PWA_POSTGRES_SKU_NAME      flexible server compute, e.g. Standard_D2s_v3
#   PWA_POSTGRES_SKU_TIER      Burstable | GeneralPurpose | MemoryOptimized
#   PWA_DEPLOY_ROLE_ASSIGNMENTS
#                              false where the web app identity's two grants are
#                              applied by the subscription administrator instead
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
: "${AZURE_LOCATION:?Set AZURE_LOCATION in ~/.azure/journeys.env — this journey hard-codes no region}"
RESOURCE_GROUP="pwa-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
echo "Deploying azure/j2-paas-web-app to subscription $SUBSCRIPTION_ID, location $AZURE_LOCATION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
APP_DIR="${SCRIPT_DIR}/../app"

# ---- resource providers ------------------------------------------------------
# A subscription that has never created these resource types rejects the
# deployment with MissingSubscriptionRegistration. Registering is idempotent.
for ns in Microsoft.Web Microsoft.DBforPostgreSQL Microsoft.Storage Microsoft.KeyVault \
  Microsoft.Insights Microsoft.OperationalInsights Microsoft.Cdn; do
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
  "Journey=azure/j2-paas-web-app" \
  --output none

# ---- generated secrets -------------------------------------------------------
# Both values are generated here and never written to the repo. They go into a
# 0600 temp file rather than the command line so they stay out of the process
# table; ARM records securestring values nowhere in deployment history.
# PostgreSQL wants >=8 characters from three of four character classes and
# rejects a password containing the login name. The random body is base64
# alphanumerics and the Aa1_ suffix guarantees all four classes.
gen_password() {
  printf '%sAa1_' "$(openssl rand -base64 24 | tr -d '/+=')"
}
DB_ADMIN_PASSWORD="$(gen_password)"
DJANGO_SECRET_KEY="$(openssl rand -base64 48 | tr -d '/+=')"

SECRET_PARAMS="$(mktemp)"
chmod 600 "$SECRET_PARAMS"
APP_ZIP="$(mktemp -u).zip"
trap 'rm -f "$SECRET_PARAMS" "$APP_ZIP"' EXIT

cat >"$SECRET_PARAMS" <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "autoTeardownDate": { "value": "${AUTOTEARDOWN_DATE}" },
    "dbAdminPassword": { "value": "${DB_ADMIN_PASSWORD}" },
    "djangoSecretKey": { "value": "${DJANGO_SECRET_KEY}" }
  }
}
JSON

# ---- infrastructure ----------------------------------------------------------
DEPLOY_NAME="pwa-deploy-$(date -u +%Y%m%d-%H%M%S)"
echo ""
echo ">>> Running deployment $DEPLOY_NAME"
echo "    (first run takes ~10-15 minutes — the PostgreSQL flexible server and"
echo "     the Front Door endpoint dominate)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOY_NAME" \
  --template-file "${BICEP_DIR}/main.bicep" \
  --parameters "@${BICEP_DIR}/main.parameters.json" \
  --parameters "@${SECRET_PARAMS}" \
  --parameters location="$AZURE_LOCATION" \
  ${PWA_APP_PLAN_SKU_NAME:+--parameters appServicePlanSkuName="${PWA_APP_PLAN_SKU_NAME}"} \
  ${PWA_APP_PLAN_SKU_TIER:+--parameters appServicePlanSkuTier="${PWA_APP_PLAN_SKU_TIER}"} \
  ${PWA_POSTGRES_SKU_NAME:+--parameters postgresSkuName="${PWA_POSTGRES_SKU_NAME}"} \
  ${PWA_POSTGRES_SKU_TIER:+--parameters postgresSkuTier="${PWA_POSTGRES_SKU_TIER}"} \
  ${PWA_DEPLOY_ROLE_ASSIGNMENTS:+--parameters deployRoleAssignments="${PWA_DEPLOY_ROLE_ASSIGNMENTS}"} \
  --output none

read_output() {
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
    --query "properties.outputs.${1}.value" -o tsv
}

BASE_URL="$(read_output baseUrl)"
ORIGIN_URL="$(read_output originUrl)"
STAGING_URL="$(read_output stagingUrl)"
WEB_APP_NAME="$(read_output webAppName)"
POSTGRES_FQDN="$(read_output postgresFqdn)"
POSTGRES_SKU="$(read_output postgresSku)"
STORAGE_ACCOUNT="$(read_output storageAccountName)"
KEY_VAULT_NAME="$(read_output keyVaultName)"

# ---- application -------------------------------------------------------------
# Plain zip deploy rather than a container: App Service builds the Python
# environment from requirements.txt with Oryx, which the SCM_DO_BUILD_DURING_
# DEPLOYMENT app setting turns on.
echo ""
echo ">>> Packaging the storefront"
python3 - "$APP_DIR" "$APP_ZIP" <<'PY'
import os
import sys
import zipfile

source, destination = sys.argv[1], sys.argv[2]
skip_dirs = {"__pycache__", ".venv", "venv", "staticfiles", ".pytest_cache"}
with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
    for root, dirs, files in os.walk(source):
        dirs[:] = sorted(d for d in dirs if d not in skip_dirs)
        for name in sorted(files):
            if name.endswith((".pyc", ".sqlite3")):
                continue
            full = os.path.join(root, name)
            archive.write(full, os.path.relpath(full, source))
print(f"packaged {destination}")
PY

echo ">>> Deploying the storefront to $WEB_APP_NAME (Oryx build, a few minutes)"
az webapp deploy \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --src-path "$APP_ZIP" \
  --type zip \
  --output none

# ---- outputs -----------------------------------------------------------------
echo ""
echo "============================================================"
echo ">>> azure/j2-paas-web-app deployed to $RESOURCE_GROUP."
echo "BASE_URL=${BASE_URL}"
echo "ORIGIN_URL=${ORIGIN_URL}"
echo "STAGING_URL=${STAGING_URL}"
echo "WEB_APP=${WEB_APP_NAME}"
echo "POSTGRES_FQDN=${POSTGRES_FQDN}"
echo "POSTGRES_SKU=${POSTGRES_SKU}"
echo "STORAGE_ACCOUNT=${STORAGE_ACCOUNT}"
echo "KEY_VAULT=${KEY_VAULT_NAME}"
echo ""

# Matched the way the CLI itself reads a bool parameter: anything but "true"
# turns the switch off, so anything but "true" earns the warning.
if [[ -n "${PWA_DEPLOY_ROLE_ASSIGNMENTS:-}" && "${PWA_DEPLOY_ROLE_ASSIGNMENTS,,}" != "true" ]]; then
  echo "Role assignments were NOT created by this deployment. Until the web app's"
  echo "identity holds Key Vault Secrets User on ${KEY_VAULT_NAME} and Storage Blob"
  echo "Data Reader on ${STORAGE_ACCOUNT}, /admin/azure-check reports those two"
  echo "services as unavailable and product images do not render."
  echo ""
fi
echo "The generated PostgreSQL administrator password and Django SECRET_KEY were"
echo "not printed and are not stored. Re-run this script to rotate them."
echo ""
echo "The database is empty until it is seeded, and the catalogue pages need it:"
echo "  ./scripts/seed.sh"
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo ""
echo "Front Door takes a few minutes to propagate its endpoint after the first"
echo "deploy. Until it does, ${ORIGIN_URL} answers immediately."
echo "============================================================"
