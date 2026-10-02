#!/usr/bin/env bash
# teardown.sh — delete every azure/j6-storage-media-pipeline resource.
# -----------------------------------------------------------------------------
# Confirmation-gated: type "yes" at the prompt, or set FORCE_TEARDOWN=1 for
# non-interactive runs.
#
# ONE resource group (smp-rg) holds the whole estate, both dialects' worth, so
# the delete is a single `az group delete`. Two things go first, in this order:
#
#   1. The time-based retention policy on the masters container. It is in the
#      Unlocked state, which still blocks overwrites and deletes of blobs
#      inside the retention window but leaves the policy itself removable, so
#      clearing it needs no special handling — just the policy's current etag.
#      A LOCKED policy could not be removed at all and the container could only
#      be deleted once empty and past retention, which is why nothing in this
#      estate locks one. This step is best-effort: it is a precondition worth
#      making explicit, not a gate on the delete.
#   2. The sync groups inside the Storage Sync Service, and THEN the service
#      itself. Microsoft documents that order and it is not optional: "After
#      you've deleted all the sync groups in that Storage Sync Service, delete
#      the Storage Sync Service resource."
#      (Microsoft Learn: azure/storage/file-sync/file-sync-modify-sync-topology)
#      A service that still has a sync group refuses to delete, and the refusal
#      propagates — `az group delete` fails with ResourceGroupDeletionBlocked and
#      NOTHING in the group is removed. Unlike step 1 this step is fatal on
#      error, so a failure surfaces here rather than as a wedged group delete.
#
# Deleting rather than emptying matters: an account left in place keeps billing
# for whatever is stored on it, and the premium share bills on its provisioned
# size whether or not anything is written to it.
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
RESOURCE_GROUP="smp-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

if ! az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "${RESOURCE_GROUP} does not exist — nothing to delete."
  rm -f "${TF_DIR}/terraform.tfstate" "${TF_DIR}/terraform.tfstate.backup"
  exit 0
fi

# ---- confirmation gate --------------------------------------------------------
echo "About to DELETE resource group ${RESOURCE_GROUP} in subscription ${SUBSCRIPTION_ID}."
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table || true

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p 'Type "yes" to confirm: ' CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted — nothing was deleted."
    exit 1
  fi
fi

# ---- 1. clear the retention policy on masters --------------------------------
MEDIA=$(az storage account list --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'smpmedia')] | [0].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$MEDIA" ]]; then
  POLICY_STATE=$(az storage container immutability-policy show \
    --resource-group "$RESOURCE_GROUP" --account-name "$MEDIA" \
    --container-name "masters" --query "[state, properties.state] | [?@] | [0]" \
    -o tsv 2>/dev/null || echo "")
  if [[ -n "$POLICY_STATE" ]]; then
    echo ">>> masters retention policy is ${POLICY_STATE}; clearing it."
    POLICY_ETAG=$(az storage container immutability-policy show \
      --resource-group "$RESOURCE_GROUP" --account-name "$MEDIA" \
      --container-name "masters" --query "[etag, properties.etag] | [?@] | [0]" \
      -o tsv 2>/dev/null || echo "")
    if [[ -n "$POLICY_ETAG" ]]; then
      az storage container immutability-policy delete \
        --resource-group "$RESOURCE_GROUP" --account-name "$MEDIA" \
        --container-name "masters" --if-match "$POLICY_ETAG" \
        --output none 2>/dev/null ||
        echo "WARNING: could not clear the masters retention policy; continuing." >&2
    fi
  else
    echo ">>> No retention policy on masters to clear."
  fi
else
  echo ">>> No smpmedia* account found — skipping the retention policy step."
fi

# ---- 2. sync groups, then the sync service, then the group --------------------
SYNC=$(az resource list --resource-group "$RESOURCE_GROUP" \
  --resource-type "Microsoft.StorageSync/storageSyncServices" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$SYNC" ]]; then
  SYNC_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
  SYNC_ID="${SYNC_ID}/providers/Microsoft.StorageSync/storageSyncServices/${SYNC}"

  # Enumerated over the management API rather than `az resource list`, which
  # does not reliably project this provider's child resources.
  SYNC_GROUP_IDS=$(az rest --method get \
    --url "https://management.azure.com${SYNC_ID}/syncGroups?api-version=2022-09-01" \
    --query "value[].id" -o tsv 2>/dev/null || echo "")
  for sg in $SYNC_GROUP_IDS; do
    echo ">>> Deleting sync group ${sg##*/}..."
    az resource delete --ids "$sg" --api-version 2022-09-01 --output none
  done

  echo ">>> Deleting storage sync service ${SYNC}..."
  az resource delete --ids "$SYNC_ID" --api-version 2022-09-01 --output none
else
  echo ">>> No storage sync service present."
fi

# ---- 3. the group -------------------------------------------------------------
echo ">>> Deleting ${RESOURCE_GROUP} (this takes several minutes)..."
az group delete --name "$RESOURCE_GROUP" --yes

if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "FATAL: ${RESOURCE_GROUP} still exists after delete — investigate before re-running." >&2
  exit 1
fi

# Local state now describes resources that no longer exist; clearing it keeps
# the next deploy.sh from trying to reconcile them.
rm -f "${TF_DIR}/terraform.tfstate" "${TF_DIR}/terraform.tfstate.backup"

echo ""
echo "azure/j6-storage-media-pipeline teardown complete — ${RESOURCE_GROUP} is gone."
