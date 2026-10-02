#!/usr/bin/env bash
# deploy.sh — deploy the azure/j7-container-apps-rag test bed (robo-advisory RAG, car-*) to Azure.
# -----------------------------------------------------------------------------
# Idempotent: `az group create` is create-or-update and `az deployment group
# create` runs in Incremental mode, so re-running converges. The image tag is
# the one moving part — re-running rebuilds and re-pushes the same tag, and the
# container app picks it up on the next revision.
#
# Everything lands in ONE resource group (car-rg) so teardown is a single
# `az group delete`.
#
# THREE STEPS, IN THIS ORDER, AND THE ORDER MATTERS:
#
#   1. bicep/registry.bicep      creates the container registry
#   2. az acr build              builds and pushes the explainer image into it
#   3. bicep/main.bicep          everything else, including the container app
#
# Step 3 cannot run before step 2. A container app whose image cannot be pulled
# provisions as Failed, and a failed child resource fails the whole deployment.
# That is why the registry is a separate template rather than another module.
#
# Deploy order inside main.bicep is expressed through module inputs: network,
# monitoring, storage and Cosmos DB first; then the model account and the search
# service; then the private endpoints that make those two reachable; then the
# container apps environment and the app; then the role assignments for the
# app's identity.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   AUTOTEARDOWN_DATE          YYYY-MM-DD for the AutoTeardown tag
#   AZURE_LOCATION             region for the resource group and everything in
#                              it — no region is hard-coded in this repository
#
# Optional per-run overrides, for a subscription whose catalogue or quota does
# not carry the template defaults:
#   CAR_OPENAI_LOCATION          region for the model account alone. Set this
#                                when AZURE_LOCATION does not offer the model at
#                                the deployment type below. Defaults to
#                                AZURE_LOCATION.
#   CAR_OPENAI_MODEL_NAME        model to deploy, e.g. gpt-5-mini
#   CAR_OPENAI_MODEL_VERSION     its version, e.g. 2025-08-07
#   CAR_OPENAI_DEPLOYMENT_SKU    GlobalStandard | Standard | DataZoneStandard
#   CAR_OPENAI_DEPLOYMENT_CAPACITY
#                                thousands of tokens per minute; 1 is the floor
#   CAR_SEARCH_SKU               basic | standard | standard2
#   CAR_LLM_MODE                 live | stub. Ships as stub — see the note at
#                                the end of this script before switching.
#   CAR_DEPLOY_ROLE_ASSIGNMENTS  false where the container app identity's Azure
#                                role assignments are applied by the subscription
#                                administrator instead
#   CAR_DEPLOY_COSMOS_DATA_PLANE_ROLE
#                                false where the Cosmos DB data-plane assignment
#                                is managed outside this template. Separate from
#                                the switch above because Contributor CAN create
#                                this one — turning that switch off should not
#                                take conversation history down with it
#   CAR_IMAGE_TAG                image tag to build and deploy (default: v1)
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
RESOURCE_GROUP="car-rg"
IMAGE_TAG="${CAR_IMAGE_TAG:-v1}"
IMAGE_REPOSITORY="car-advisor"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
echo "Deploying azure/j7-container-apps-rag to subscription $SUBSCRIPTION_ID, location $AZURE_LOCATION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
APP_DIR="${SCRIPT_DIR}/../app/advisor"

# ---- resource providers ------------------------------------------------------
# A subscription that has never created these resource types rejects the
# deployment with MissingSubscriptionRegistration. Registering is idempotent.
#
# Microsoft.ContainerService is in the list even though nothing here is a
# Kubernetes cluster: Microsoft requires it registered before a container apps
# environment can be created in a virtual network, and a subscription that has
# never run AKS does not have it.
for ns in Microsoft.App Microsoft.ContainerService Microsoft.ContainerRegistry \
  Microsoft.CognitiveServices Microsoft.Search Microsoft.DocumentDB \
  Microsoft.Storage Microsoft.Network Microsoft.OperationalInsights \
  Microsoft.Insights; do
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
  "Journey=azure/j7-container-apps-rag" \
  --output none

# The teardown date is the only value both templates need that is not in a
# parameters file. It goes into a 0600 temp file for consistency with the rest
# of the estate rather than onto a command line.
SHARED_PARAMS="$(mktemp)"
chmod 600 "$SHARED_PARAMS"
trap 'rm -f "$SHARED_PARAMS"' EXIT

cat >"$SHARED_PARAMS" <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "autoTeardownDate": { "value": "${AUTOTEARDOWN_DATE}" }
  }
}
JSON

# ---- step 1: the registry ----------------------------------------------------
REGISTRY_DEPLOY_NAME="car-registry-$(date -u +%Y%m%d-%H%M%S)"
echo ""
echo ">>> Running deployment $REGISTRY_DEPLOY_NAME (container registry)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$REGISTRY_DEPLOY_NAME" \
  --template-file "${BICEP_DIR}/registry.bicep" \
  --parameters "@${SHARED_PARAMS}" \
  --parameters location="$AZURE_LOCATION" \
  --output none

read_registry_output() {
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" --name "$REGISTRY_DEPLOY_NAME" \
    --query "properties.outputs.${1}.value" -o tsv
}

REGISTRY_NAME="$(read_registry_output registryName)"
LOGIN_SERVER="$(read_registry_output loginServer)"
CONTAINER_IMAGE="${LOGIN_SERVER}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"

# ---- step 2: the image -------------------------------------------------------
# Built by the registry's own build service rather than locally, so no Docker
# daemon is needed on the machine running this script.
echo ""
echo ">>> Building ${IMAGE_REPOSITORY}:${IMAGE_TAG} in ${REGISTRY_NAME} (a few minutes)"
az acr build \
  --registry "$REGISTRY_NAME" \
  --image "${IMAGE_REPOSITORY}:${IMAGE_TAG}" \
  --file "${APP_DIR}/Dockerfile" \
  "$APP_DIR" \
  --output none

# ---- step 3: everything else -------------------------------------------------
DEPLOY_NAME="car-deploy-$(date -u +%Y%m%d-%H%M%S)"
echo ""
echo ">>> Running deployment $DEPLOY_NAME"
echo "    (first run takes ~15-20 minutes — the container apps environment and"
echo "     the two private endpoints dominate)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOY_NAME" \
  --template-file "${BICEP_DIR}/main.bicep" \
  --parameters "@${BICEP_DIR}/main.parameters.json" \
  --parameters "@${SHARED_PARAMS}" \
  --parameters location="$AZURE_LOCATION" \
  --parameters registryName="$REGISTRY_NAME" \
  --parameters containerImage="$CONTAINER_IMAGE" \
  --parameters openAiLocation="${CAR_OPENAI_LOCATION:-$AZURE_LOCATION}" \
  ${CAR_OPENAI_MODEL_NAME:+--parameters openAiModelName="${CAR_OPENAI_MODEL_NAME}"} \
  ${CAR_OPENAI_MODEL_VERSION:+--parameters openAiModelVersion="${CAR_OPENAI_MODEL_VERSION}"} \
  ${CAR_OPENAI_DEPLOYMENT_SKU:+--parameters openAiDeploymentSku="${CAR_OPENAI_DEPLOYMENT_SKU}"} \
  ${CAR_OPENAI_DEPLOYMENT_CAPACITY:+--parameters openAiDeploymentCapacity="${CAR_OPENAI_DEPLOYMENT_CAPACITY}"} \
  ${CAR_SEARCH_SKU:+--parameters searchSku="${CAR_SEARCH_SKU}"} \
  ${CAR_LLM_MODE:+--parameters llmMode="${CAR_LLM_MODE}"} \
  ${CAR_DEPLOY_ROLE_ASSIGNMENTS:+--parameters deployRoleAssignments="${CAR_DEPLOY_ROLE_ASSIGNMENTS}"} \
  ${CAR_DEPLOY_COSMOS_DATA_PLANE_ROLE:+--parameters deployCosmosDataPlaneRole="${CAR_DEPLOY_COSMOS_DATA_PLANE_ROLE}"} \
  --output none

read_output() {
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
    --query "properties.outputs.${1}.value" -o tsv
}

BASE_URL="$(read_output baseUrl)"
CONTAINER_APP_NAME="$(read_output containerAppName)"
OPENAI_ACCOUNT="$(read_output openAiAccountName)"
OPENAI_REGION="$(read_output openAiLocation)"
OPENAI_DEPLOYMENT="$(read_output openAiDeploymentName)"
CONTENT_POLICY="$(read_output contentPolicyName)"
SEARCH_SERVICE="$(read_output searchServiceName)"
SEARCH_TIER="$(read_output searchSku)"
STORAGE_ACCOUNT="$(read_output storageAccountName)"
COSMOS_ACCOUNT="$(read_output cosmosAccountName)"
RUNNING_MODE="$(read_output llmMode)"

# ---- outputs -----------------------------------------------------------------
echo ""
echo "============================================================"
echo ">>> azure/j7-container-apps-rag deployed to $RESOURCE_GROUP."
echo "BASE_URL=${BASE_URL}"
echo "CONTAINER_APP=${CONTAINER_APP_NAME}"
echo "IMAGE=${CONTAINER_IMAGE}"
echo "REGISTRY=${REGISTRY_NAME}"
echo "OPENAI_ACCOUNT=${OPENAI_ACCOUNT} (${OPENAI_REGION})"
echo "OPENAI_DEPLOYMENT=${OPENAI_DEPLOYMENT}"
echo "CONTENT_POLICY=${CONTENT_POLICY}"
echo "SEARCH_SERVICE=${SEARCH_SERVICE} (${SEARCH_TIER})"
echo "STORAGE_ACCOUNT=${STORAGE_ACCOUNT}"
echo "COSMOS_ACCOUNT=${COSMOS_ACCOUNT}"
echo "LLM_MODE=${RUNNING_MODE}"
echo ""

if [[ -n "${CAR_DEPLOY_ROLE_ASSIGNMENTS:-}" && "${CAR_DEPLOY_ROLE_ASSIGNMENTS,,}" != "true" ]]; then
  echo "Azure role assignments were NOT created by this deployment. Until the"
  echo "container app's identity holds Cognitive Services OpenAI User on"
  echo "${OPENAI_ACCOUNT}, Search Service Contributor and Search Index Data"
  echo "Contributor on ${SEARCH_SERVICE}, and Storage Blob Data Reader on"
  echo "${STORAGE_ACCOUNT}, /admin/azure-check reports those services as"
  echo "unavailable, ./scripts/seed.sh cannot build the index, and every"
  echo "explanation comes back uncited. Conversation history is unaffected — the"
  echo "Cosmos grant is a separate switch, because it needs only Contributor."
  echo ""
fi

if [[ -n "${CAR_DEPLOY_COSMOS_DATA_PLANE_ROLE:-}" && "${CAR_DEPLOY_COSMOS_DATA_PLANE_ROLE,,}" != "true" ]]; then
  echo "The Cosmos DB data-plane assignment was NOT created. Until the container"
  echo "app's identity holds it on ${COSMOS_ACCOUNT}, /health reports the"
  echo "conversation store as unavailable, /explain answers with \"stored\": false,"
  echo "and /history returns 404 for every session."
  echo ""
fi

if [[ "$RUNNING_MODE" == "stub" ]]; then
  echo "The explainer is running in stub mode. Retrieval, citation and history all"
  echo "work; only the final paragraph is composed locally instead of by the model."
  echo "Before switching to live, confirm the deployment actually has quota:"
  echo "  az cognitiveservices usage list --location ${OPENAI_REGION} -o table"
  echo "then re-run with CAR_LLM_MODE=live."
  echo ""
fi

echo "The index is empty until the documentation is loaded, and every explanation"
echo "comes back uncited until it is:"
echo "  ./scripts/seed.sh"
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo ""
echo "A scaled-to-zero app answers its first request in a few seconds while a"
echo "replica starts. That is expected, not a fault."
echo "============================================================"
