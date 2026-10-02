#!/usr/bin/env bash
# teardown.sh — destroy the azure/j7-container-apps-rag test bed.
# -----------------------------------------------------------------------------
# The whole estate lives in one resource group, so teardown is essentially a
# single `az group delete`. It DELETES rather than stops: a container apps
# environment that is merely idle still bills for its load balancer and its
# egress address.
#
# Three things need more than the group delete, and all three are handled here.
#
# 1. THE PRIVATE ENDPOINTS AND THE ENVIRONMENT COME OUT FIRST. Azure Resource
#    Manager works out its own delete order for a resource group and retries for
#    15 minutes, and Microsoft states plainly that deleting the group also
#    removes the managed resource group the container apps platform created. On
#    paper that is enough. Two things make it worth not relying on: there is a
#    whole class of resource whose private endpoint blocks the delete of its
#    target — a Recovery Services vault is the documented example — and the
#    environment holds a service association link on the delegated `apps`
#    subnet, which has to come off before the subnet and the network can go.
#    Both pre-deletes are non-fatal: if either fails, the group delete runs
#    anyway and does its own sequencing.
#
# 2. THE WORKSPACE SURVIVES THE RESOURCE GROUP. Deleting the group soft-deletes
#    the Log Analytics workspace for 14 days and reserves its name. `car-logs`
#    is a fixed name with no uniqueness suffix, so a re-deploy either silently
#    recovers the old workspace with the old data still in it, or — if the region
#    changed — fails outright. The permanent delete below closes that off.
#
# 3. THE MODEL ACCOUNT SURVIVES THE RESOURCE GROUP TOO. Azure soft-deletes a
#    Cognitive Services account and holds its name — and its custom subdomain —
#    for 48 hours. The account name is derived from the resource group id, so a
#    re-deploy into the same group computes the same name and fails against the
#    soft-deleted record. This script purges it. The purge needs
#    Microsoft.CognitiveServices/locations/resourceGroups/deletedAccounts/delete,
#    which Contributor only carries at subscription scope.
#
# The search service, the registry and the Cosmos DB account have no soft delete
# and no purge — their names are free the moment they are gone.
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
RESOURCE_GROUP="car-rg"

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
# The purge below is addressed by region, and the account's own record is the
# only trustworthy source for that — no region is hard-coded in this repository.
OPENAI_ACCOUNT=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")
OPENAI_LOCATION=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" \
  --query "[0].location" -o tsv 2>/dev/null || echo "")

# ---- confirmation ------------------------------------------------------------
echo "About to DELETE resource group ${RESOURCE_GROUP} in subscription ${SUBSCRIPTION_ID}."
echo "Everything in azure/j7-container-apps-rag goes with it:"
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

# ---- private endpoints, ahead of the group -----------------------------------
PRIVATE_ENDPOINTS=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" \
  --query "[].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$PRIVATE_ENDPOINTS" ]]; then
  echo ""
  echo ">>> Removing private endpoints before the group"
  while read -r pe; do
    [[ -z "$pe" ]] && continue
    echo "    ${pe}"
    az network private-endpoint delete \
      --resource-group "$RESOURCE_GROUP" --name "$pe" --output none 2>/dev/null ||
      echo "    could not delete ${pe} — leaving it to the group delete" >&2
  done <<<"$PRIVATE_ENDPOINTS"
fi

# ---- the environment, ahead of the network it is linked into -----------------
CONTAINER_ENV=$(az containerapp env list --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$CONTAINER_ENV" ]]; then
  echo ""
  echo ">>> Removing container apps environment ${CONTAINER_ENV} before the group"
  echo "    (several minutes — it releases the delegated subnet and its managed group)"
  az containerapp env delete \
    --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_ENV" --yes --output none 2>/dev/null ||
    echo "    could not delete ${CONTAINER_ENV} — leaving it to the group delete" >&2
fi

# ---- the workspace, permanently rather than softly ---------------------------
# --force is what makes this a permanent delete. Without it the workspace is
# soft-deleted with the group and its name is reserved for 14 days, and because
# car-logs carries no uniqueness suffix, the next deployment into this group
# either recovers the old workspace with the old data or fails outright.
WORKSPACE=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$WORKSPACE" ]]; then
  echo ""
  echo ">>> Permanently deleting Log Analytics workspace ${WORKSPACE}"
  az monitor log-analytics workspace delete \
    --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE" \
    --force true --yes --output none 2>/dev/null ||
    echo "    could not permanently delete ${WORKSPACE} — it will be soft-deleted with the group, and its name is then held for 14 days" >&2
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

# ---- purge the soft-deleted model account ------------------------------------
if [[ -n "$OPENAI_ACCOUNT" && -n "$OPENAI_LOCATION" ]]; then
  echo ">>> Purging soft-deleted model account ${OPENAI_ACCOUNT} (${OPENAI_LOCATION})"
  # The first-class command, not `az resource delete --ids` against the
  # deletedAccounts path: that path has no api-version the CLI can resolve on
  # its own. stderr is left alone so a real failure says what it actually was.
  if az cognitiveservices account purge \
    --location "$OPENAI_LOCATION" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$OPENAI_ACCOUNT" --output none; then
    echo "    purged."
  else
    echo "    could not purge ${OPENAI_ACCOUNT} — it may already be gone, or the" >&2
    echo "    signed-in principal may lack" >&2
    echo "    Microsoft.CognitiveServices/locations/resourceGroups/deletedAccounts/delete" >&2
    echo "    at subscription scope. Until it is purged, the name and its custom" >&2
    echo "    subdomain are held for 48 hours and a re-deploy into ${RESOURCE_GROUP}" >&2
    echo "    fails, because the name is derived from the resource group id." >&2
  fi
fi

echo ""
echo "============================================================"
echo ">>> azure/j7-container-apps-rag torn down. ${RESOURCE_GROUP} is gone."
echo "Confirm nothing survived subscription-wide:"
echo "  az resource list --tag Journey=azure/j7-container-apps-rag -o table"
echo "  az cognitiveservices account list-deleted --query \"[?name=='${OPENAI_ACCOUNT}']\" -o table"
echo "============================================================"
