#!/usr/bin/env bash
# deploy.sh — deploy the azure/j8-clickops-partial-iac student portal (cpi-*) to Azure.
# -----------------------------------------------------------------------------
# Idempotent: `az group create` is create-or-update and `az deployment group
# create` runs in Incremental mode, so re-running converges. One caveat — the
# SQL administrator password is regenerated on every run, so a re-deploy ROTATES
# it. It is never written to this repository and never printed.
#
# Everything this script creates lands in ONE resource group (cpi-rg) so
# teardown is a single `az group delete`. Note what that does NOT mean: the
# template covers the student portal only. The rest of the university's Azure
# estate was never captured in a template and is not created, updated or removed
# by anything here.
#
# Deploy order is expressed through Bicep module inputs in bicep/main.bicep:
# the storage account and the SQL database first, then the web app, whose
# configuration is composed from both. The application itself is pushed
# afterwards as a zip and built on the server by Oryx.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   AUTOTEARDOWN_DATE          YYYY-MM-DD for the AutoTeardown tag
#   AZURE_LOCATION             region for the resource group and everything in
#                              it — no region is hard-coded in this repository
# Optional per-run overrides, for a subscription whose catalogue does not carry
# the template defaults (B1 / Basic):
#   CPI_APP_PLAN_SKU_NAME      App Service plan SKU, e.g. S1 (must keep always-on,
#   CPI_APP_PLAN_SKU_TIER      so Free and Shared will not do)
#   CPI_SQL_DB_SKU_NAME        SQL service objective, e.g. S0
#   CPI_SQL_DB_SKU_TIER        service tier matching the objective, e.g. Standard
#   CPI_PYTHON_VERSION         Python runtime for the site, e.g. 3.11
# And one for a region where the first container start is slow:
#   CPI_SITE_READY_TIMEOUT     seconds to wait for the portal to answer, default 300
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
RESOURCE_GROUP="cpi-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
echo "Deploying azure/j8-clickops-partial-iac to subscription $SUBSCRIPTION_ID, location $AZURE_LOCATION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
APP_DIR="${SCRIPT_DIR}/../app"

# ---- resource providers ------------------------------------------------------
# A subscription that has never created these resource types rejects the
# deployment with MissingSubscriptionRegistration. Registering is idempotent.
for ns in Microsoft.Web Microsoft.Sql Microsoft.Storage; do
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
  "Journey=azure/j8-clickops-partial-iac" \
  --output none

# ---- generated secret --------------------------------------------------------
# Generated here and never written to the repo. It goes into a 0600 temp file
# rather than the command line so it stays out of the process table; ARM records
# securestring values nowhere in deployment history.
#
# Azure SQL wants >=8 characters from three of four character classes and
# rejects a password containing the login name. The random body is base64
# alphanumerics and the Aa1_ suffix guarantees all four classes.
gen_password() {
  printf '%sAa1_' "$(openssl rand -base64 24 | tr -d '/+=')"
}
SQL_ADMIN_PASSWORD="$(gen_password)"

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
    "sqlAdminPassword": { "value": "${SQL_ADMIN_PASSWORD}" }
  }
}
JSON

# ---- infrastructure ----------------------------------------------------------
DEPLOY_NAME="cpi-deploy-$(date -u +%Y%m%d-%H%M%S)"
echo ""
echo ">>> Running deployment $DEPLOY_NAME"
echo "    (first run takes ~5-8 minutes — the SQL logical server dominates)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOY_NAME" \
  --template-file "${BICEP_DIR}/main.bicep" \
  --parameters "@${BICEP_DIR}/main.parameters.json" \
  --parameters "@${SECRET_PARAMS}" \
  --parameters location="$AZURE_LOCATION" \
  ${CPI_APP_PLAN_SKU_NAME:+--parameters appServicePlanSkuName="${CPI_APP_PLAN_SKU_NAME}"} \
  ${CPI_APP_PLAN_SKU_TIER:+--parameters appServicePlanSkuTier="${CPI_APP_PLAN_SKU_TIER}"} \
  ${CPI_SQL_DB_SKU_NAME:+--parameters sqlDatabaseSkuName="${CPI_SQL_DB_SKU_NAME}"} \
  ${CPI_SQL_DB_SKU_TIER:+--parameters sqlDatabaseSkuTier="${CPI_SQL_DB_SKU_TIER}"} \
  ${CPI_PYTHON_VERSION:+--parameters pythonVersion="${CPI_PYTHON_VERSION}"} \
  --output none

read_output() {
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
    --query "properties.outputs.${1}.value" -o tsv
}

BASE_URL="$(read_output baseUrl)"
WEB_APP_NAME="$(read_output webAppName)"
APP_PLAN_SKU="$(read_output appServicePlanSku)"
SQL_SERVER_NAME="$(read_output sqlServerName)"
SQL_SERVER_FQDN="$(read_output sqlServerFqdn)"
SQL_DATABASE_NAME="$(read_output sqlDatabaseName)"
SQL_DATABASE_SKU="$(read_output sqlDatabaseSku)"
STORAGE_ACCOUNT="$(read_output storageAccountName)"
DOCUMENTS_CONTAINER="$(read_output documentsContainerName)"

# ---- application -------------------------------------------------------------
# Plain zip deploy rather than a container: App Service builds the Python
# environment from requirements.txt with Oryx, which the SCM_DO_BUILD_DURING_
# DEPLOYMENT app setting turns on.
echo ""
echo ">>> Packaging the portal"
# Same packager scripts/app-self-test.sh uses, so what is tested locally and what
# is pushed here are the same archive layout.
python3 "${SCRIPT_DIR}/package-app.py" "$APP_DIR" "$APP_ZIP"

# A failed zip deploy can only be investigated while the resource group is still
# there, and the usual next move after a failure is to tear the group down —
# which takes the platform's logs with it. So everything needed to work out why
# the worker did not start is written to one file first.
#
# Setting VALUES are never read: the storage account key and the SQL password are
# in that collection, and this file is meant to be safe to paste into a bug
# report. Names only.
collect_deploy_diagnostics() {
  local out="$1"
  local reason="$2"
  local logs_zip="${out%.log}-LogFiles.zip"
  {
    echo "=== ${reason} at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    echo "resource group : ${RESOURCE_GROUP}"
    echo "site           : ${WEB_APP_NAME}"
    echo "plan SKU       : ${APP_PLAN_SKU}"
    echo ""
    echo "Reading the container log: a site that has a startup command but no code"
    echo "yet cannot start, so a first deployment always leaves two or three"
    echo "\"exited with exit code 3\" records from before the zip arrived. Those say"
    echo "\"Could not find virtual environment directory\" and name the application"
    echo "module as missing. The start that matters is the one after the build."
    echo ""
    echo "=== site configuration: runtime and startup command ==="
    az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" \
      --query "{state:state, linuxFxVersion:siteConfig.linuxFxVersion, appCommandLine:siteConfig.appCommandLine, alwaysOn:siteConfig.alwaysOn, healthCheckPath:siteConfig.healthCheckPath, workers:siteConfig.numberOfWorkers}" \
      -o yaml 2>&1 || echo "(could not read the site configuration)"
    echo ""
    echo "=== application setting names (values not read) ==="
    az webapp config appsettings list --resource-group "$RESOURCE_GROUP" \
      --name "$WEB_APP_NAME" --query "[].name" -o tsv 2>&1 ||
      echo "(could not read the setting names)"
    echo ""
    echo "=== last deployment record, including the Oryx build output ==="
    az webapp log deployment show --resource-group "$RESOURCE_GROUP" \
      --name "$WEB_APP_NAME" 2>&1 | tail -120 ||
      echo "(no deployment record available)"
    echo ""
    echo "=== container and startup logs ==="
    if az webapp log download --resource-group "$RESOURCE_GROUP" \
      --name "$WEB_APP_NAME" --log-file "$logs_zip" >/dev/null 2>&1; then
      echo "wrote ${logs_zip}"
      echo "LogFiles/StartupLogs/*_failure.log inside it carries the traceback"
      echo "behind an exit code, and it is the only copy that survives teardown."
    else
      echo "(the log archive would not download — the CLI warns that it may not"
      echo " work on Linux sites. Use: az webapp log tail --resource-group"
      echo " ${RESOURCE_GROUP} --name ${WEB_APP_NAME})"
    fi
  } >"$out" 2>&1
}

# Whether the portal is actually up is decided here rather than taken from the
# CLI's exit status, because the two verdicts are not the same claim.
#
# A site created with a startup command has something to run only once a zip has
# landed. Until then every container start does the same thing: Oryx finds no
# built environment, gunicorn runs from the image's own packages, importing the
# portal fails and the container exits 3. A first deployment leaves two or three
# of those, and the platform records each against the site. `az webapp deploy`
# tracks Linux site startup and reads that record, so it can poll for its full
# ten minutes and then call the deployment failed while the container that starts
# after the build is on its way up. Turning the tracker off where the CLI takes
# the flag removes a ten-minute wait for a verdict about a container that was
# never carrying this code.
#
# What replaces it is narrower and answers about this deployment: ask the site
# for the health path the template already points the platform at, and give it
# five minutes to answer 200.
SITE_READY_TIMEOUT="${CPI_SITE_READY_TIMEOUT:-300}"

wait_for_site_ready() {
  local url="${BASE_URL}/health"
  local started elapsed code next_notice=60
  started=$(date +%s)
  while :; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$url" 2>/dev/null) || code="000"
    elapsed=$(($(date +%s) - started))
    if [[ "$code" == "200" ]]; then
      echo "    ${url} answered 200 after ${elapsed}s"
      return 0
    fi
    if ((elapsed >= SITE_READY_TIMEOUT)); then
      return 1
    fi
    if ((elapsed >= next_notice)); then
      echo "    still waiting (${elapsed}s of ${SITE_READY_TIMEOUT}s, last response ${code})"
      next_notice=$((elapsed + 60))
    fi
    sleep 10
  done
}

DEPLOY_ARGS=(
  --resource-group "$RESOURCE_GROUP"
  --name "$WEB_APP_NAME"
  --src-path "$APP_ZIP"
  --type zip
  --output none
)
if az webapp deploy --help 2>/dev/null | grep -q -- "--track-status"; then
  DEPLOY_ARGS+=(--track-status false)
fi

echo ""
echo ">>> Deploying the portal to $WEB_APP_NAME (Oryx build, a few minutes)"
DEPLOY_RC=0
az webapp deploy "${DEPLOY_ARGS[@]}" || DEPLOY_RC=$?
if ((DEPLOY_RC != 0)); then
  echo ""
  echo "    az webapp deploy exited ${DEPLOY_RC}. That can mean the build failed and"
  echo "    it can mean the CLI stopped watching while the platform was still"
  echo "    restarting the site, so the site gets asked before anything is decided."
fi

echo ""
echo ">>> Waiting for the portal to serve ${BASE_URL}/health (up to ${SITE_READY_TIMEOUT}s)"
DIAGNOSTICS="${TMPDIR:-/tmp}/cpi-deploy-diagnostics-$(date -u +%Y%m%d-%H%M%S).log"
if ! wait_for_site_ready; then
  echo ""
  echo ">>> The portal did not come up. Collecting what the platform will still answer."
  collect_deploy_diagnostics "$DIAGNOSTICS" "the portal did not answer within ${SITE_READY_TIMEOUT}s"
  echo ""
  echo "============================================================"
  echo "Wrote ${DIAGNOSTICS}"
  echo ""
  echo "Read it BEFORE ./scripts/teardown.sh: deleting ${RESOURCE_GROUP} takes the"
  echo "platform's logs with it and the failure becomes unreproducible."
  echo ""
  echo "For the live container log — the one that says why the worker exited —"
  echo "run this now, while the site still exists:"
  echo "  az webapp log tail --resource-group ${RESOURCE_GROUP} --name ${WEB_APP_NAME}"
  echo ""
  echo "To reproduce the boot locally, with no subscription involved:"
  echo "  ./scripts/app-self-test.sh"
  echo "============================================================"
  exit 1
fi

if ((DEPLOY_RC != 0)); then
  # Serving, but something did report a failure. On a re-deploy the container
  # answering can still be the previous one, so this is not waved through.
  collect_deploy_diagnostics "$DIAGNOSTICS" "az webapp deploy exited ${DEPLOY_RC} but the portal is serving"
  echo ""
  echo "    The portal is serving. The deployment record is in ${DIAGNOSTICS};"
  echo "    check the Oryx build summary there before trusting the running code."
fi

# ---- outputs -----------------------------------------------------------------
echo ""
echo "============================================================"
echo ">>> azure/j8-clickops-partial-iac deployed to $RESOURCE_GROUP."
echo "BASE_URL=${BASE_URL}"
echo "WEB_APP=${WEB_APP_NAME}"
echo "APP_PLAN_SKU=${APP_PLAN_SKU}"
echo "SQL_SERVER=${SQL_SERVER_NAME}"
echo "SQL_FQDN=${SQL_SERVER_FQDN}"
echo "SQL_DATABASE=${SQL_DATABASE_NAME}"
echo "SQL_DATABASE_SKU=${SQL_DATABASE_SKU}"
echo "STORAGE_ACCOUNT=${STORAGE_ACCOUNT}"
echo "DOCUMENTS_CONTAINER=${DOCUMENTS_CONTAINER}"
echo ""
echo "The generated SQL administrator password was not printed and is not"
echo "stored here. It lives in the site's PortalDb connection string, which is"
echo "where scripts/seed.sh reads it from. Re-run this script to rotate it."
echo ""
echo "The notice board is empty and the document library has nothing in it"
echo "until the portal is seeded:"
echo "  ./scripts/seed.sh"
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo "============================================================"
