#!/usr/bin/env bash
# deploy.sh — deploy the azure/j4-durable-functions-pipeline test bed (fictional,
# dfp-*) to Azure.
# -----------------------------------------------------------------------------
# Idempotent: `az group create` is create-or-update and `az deployment group
# create` runs in Incremental mode, so re-running converges. The function app's
# code is re-packaged and re-pushed on every run, which is also convergent —
# zip deploy replaces the whole package.
#
# Everything lands in ONE resource group (dfp-rg) so teardown is a single
# `az group delete`.
#
# Deploy order is Bicep's problem. infra/main.bicep chains it: Log Analytics ->
# Application Insights, then the storage module, then the messaging module, then
# the function app (which takes both of their names as parameters), then the
# Event Grid module (which takes the storage account id). Function CODE is
# pushed afterwards, from this script, because a zip deploy is a data-plane
# operation the template cannot express.
#
# There are no securestring parameters: this estate holds no passwords. Every
# connection string in the app settings is built inside the template from
# listKeys() at deployment time, so no credential is ever written to this
# repository or passed on a command line.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   AUTOTEARDOWN_DATE          YYYY-MM-DD for the AutoTeardown tag
#   AZURE_LOCATION             region for the resource group (no fallback) —
#                              every resource inherits it from the group
#
# Also required on PATH: az, npm (the function app's runtime dependencies are
# installed locally and shipped inside the package — Windows plans do not build
# on the server), python3 (builds the zip).
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
RESOURCE_GROUP="dfp-rg"

for tool in az npm python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "FATAL: $tool is required and was not found on PATH" >&2
    exit 1
  }
done

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
echo "Deploying azure/j4-durable-functions-pipeline to subscription $SUBSCRIPTION_ID, location $AZURE_LOCATION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"
APP_DIR="${SCRIPT_DIR}/../app/claims-pipeline"

# ---- resource providers ------------------------------------------------------
# A subscription that has never created these resource types rejects the
# deployment with MissingSubscriptionRegistration. Registering is idempotent.
for ns in Microsoft.Storage Microsoft.Web Microsoft.ServiceBus Microsoft.EventGrid Microsoft.Insights Microsoft.OperationalInsights; do
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
  "Journey=azure/j4-durable-functions-pipeline" \
  --output none

# ---- infrastructure ----------------------------------------------------------
DEPLOY_NAME="dfp-deploy-$(date -u +%Y%m%d-%H%M%S)"
echo ""
echo ">>> Running deployment $DEPLOY_NAME"
echo "    (first run takes ~4-6 minutes — the Service Bus namespace dominates)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOY_NAME" \
  --template-file "${INFRA_DIR}/main.bicep" \
  --parameters "@${INFRA_DIR}/main.parameters.json" \
  --parameters "autoTeardownDate=${AUTOTEARDOWN_DATE}" \
  --output none

read_output() {
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
    --query "properties.outputs.$1.value" -o tsv
}

CLAIMS_STORAGE_ACCOUNT=$(read_output claimsStorageAccount)
INTAKE_CONTAINER=$(read_output intakeContainer)
CLAIM_STATE_TABLE=$(read_output claimStateTable)
SERVICE_BUS_NAMESPACE=$(read_output serviceBusNamespace)
REVIEW_QUEUE=$(read_output reviewQueue)
FUNCTION_APP_NAME=$(read_output functionAppName)
FUNCTION_APP_HOST=$(read_output functionAppHostName)

# ---- function code -----------------------------------------------------------
# Windows plans do not run a build on the server, so runtime dependencies are
# installed here and shipped inside the package. `config-zip` posts the archive
# to the app's deployment endpoint and the host restarts onto it.
echo ""
echo ">>> Installing runtime dependencies for the claims pipeline"
npm --prefix "$APP_DIR" install --omit=dev --no-audit --no-fund --loglevel=error

ZIP_PATH="${TMPDIR:-/tmp}/dfp-claims-pipeline-$$.zip"
trap 'rm -f "$ZIP_PATH"' EXIT

python3 - "$APP_DIR" "$ZIP_PATH" <<'PY'
import os
import sys
import zipfile

source, destination = sys.argv[1], sys.argv[2]
skip_dirs = {".git", ".vscode", "__pycache__"}
skip_files = {"local.settings.json"}

with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
    for root, dirs, files in os.walk(source):
        dirs[:] = sorted(d for d in dirs if d not in skip_dirs)
        for name in sorted(files):
            if name in skip_files:
                continue
            full = os.path.join(root, name)
            archive.write(full, os.path.relpath(full, source))
PY

echo ">>> Pushing the claims pipeline to $FUNCTION_APP_NAME"
az functionapp deployment source config-zip \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FUNCTION_APP_NAME" \
  --src "$ZIP_PATH" \
  --output none

# ---- outputs -----------------------------------------------------------------
echo ""
echo "============================================================"
echo ">>> azure/j4-durable-functions-pipeline deployed to $RESOURCE_GROUP."
echo "CLAIMS_STORAGE_ACCOUNT=${CLAIMS_STORAGE_ACCOUNT}"
echo "INTAKE_CONTAINER=${INTAKE_CONTAINER}"
echo "CLAIM_STATE_TABLE=${CLAIM_STATE_TABLE}"
echo "SERVICE_BUS_NAMESPACE=${SERVICE_BUS_NAMESPACE}"
echo "REVIEW_QUEUE=${REVIEW_QUEUE}"
echo "FUNCTION_APP=${FUNCTION_APP_NAME} (${FUNCTION_APP_HOST})"
echo ""
echo "There is no BASE_URL: this pipeline has no HTTP edge. Work reaches it by"
echo "a claim document landing in the ${INTAKE_CONTAINER} container."
echo ""
echo "No credential was printed or stored. The app settings carry connection"
echo "strings the template built from listKeys() at deployment time; re-running"
echo "this script rebuilds them from whatever the current account keys are."
echo ""
echo "Give the host a minute to sync triggers after the code push, then:"
echo "  ./scripts/smoke-test.sh azure"
echo "============================================================"
