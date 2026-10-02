#!/usr/bin/env bash
# teardown.sh — delete every azure/j5-vmss-sql-iaas resource.
# -----------------------------------------------------------------------------
# Confirmation-gated: type "yes" at the prompt, or set FORCE_TEARDOWN=1 for
# non-interactive runs.
#
# THE ORDER IS NOT OPTIONAL. A Recovery Services vault deletes cleanly with its
# resource group only while it is EMPTY. Once a machine is protected, the vault
# holds backup data and `az group delete` fails with
#
#     Vault cannot be deleted as there are existing resources within the vault.
#
# and leaves the whole group behind — the VMs keep billing and keep consuming
# regional vCPU quota. Soft delete makes this worse rather than better: the
# argument that used to disable it was removed from the Terraform provider in
# 5.0, and Azure no longer permits disabling it in the regions where
# secure-by-default is generally available. So the order is:
#
#   1. disable protection on every protected item, of every backup management
#      type, WITH --delete-backup-data, and wait until nothing is ACTIVELY
#      protected any more
#   2. delete the vault with --force, which cascades anything step 1 missed
#      (it engages only on that error substring, so it is safe to run blind)
#   3. az group delete
#   4. verify the group is gone
#
# Step 1 does NOT empty the vault, and waiting for it to empty would hang.
# Under secure-by-default an item deleted with --delete-backup-data goes to a
# soft-deleted state, stays in the list API for 14 days, and cannot be purged
# early. Azure permits deleting a vault that is empty OR that holds only
# soft-deleted items, so steps 2 and 3 proceed regardless — it is only why the
# vault name may keep appearing in a portal listing for a fortnight afterwards.
#
# Deleting rather than deallocating matters: a deallocated VM stops compute
# billing but still consumes regional vCPU quota.
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
RESOURCE_GROUP="vsi-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

if ! az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "${RESOURCE_GROUP} does not exist — nothing to delete."
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

# ---- 1. empty the vault -------------------------------------------------------
VAULT=$(az backup vault list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")

if [[ -n "$VAULT" ]]; then
  echo ">>> Vault ${VAULT} found. Disabling protection on every item it holds."

  # `az backup item list` will not answer without a backup management type, and
  # a vault is not restricted to one. This template only ever creates an
  # AzureIaasVM item, but a hand-run experiment against the same vault — a file
  # share, a SQL-in-VM workload — leaves an item that would block the group
  # delete just as hard, so sweep all three types the way the CLI's own force
  # delete does. Types with nothing under them list empty and cost one call.
  BACKUP_TYPES=(AzureIaasVM AzureWorkload AzureStorage)

  FOUND_ITEMS=0
  for BMT in "${BACKUP_TYPES[@]}"; do
    ITEMS=$(az backup item list --resource-group "$RESOURCE_GROUP" --vault-name "$VAULT" \
      --backup-management-type "$BMT" \
      --query "[].{container:properties.containerName, item:properties.friendlyName}" \
      -o tsv 2>/dev/null || echo "")
    [[ -z "$ITEMS" ]] && continue
    FOUND_ITEMS=1

    while IFS=$'\t' read -r CONTAINER ITEM; do
      [[ -z "${ITEM:-}" ]] && continue
      echo ">>> Disabling protection for ${ITEM} (${BMT}) and deleting its backup data..."
      az backup protection disable \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$VAULT" \
        --container-name "$CONTAINER" \
        --item-name "$ITEM" \
        --backup-management-type "$BMT" \
        --delete-backup-data true \
        --yes \
        --output none || echo "WARNING: disabling protection for ${ITEM} reported an error; continuing." >&2
    done <<<"$ITEMS"
  done

  if [[ "$FOUND_ITEMS" == "0" ]]; then
    echo ">>> The vault holds no protected items."
  else
    # What we wait for is that nothing is still ACTIVELY protected — not that
    # the item list is empty, which under secure-by-default it never becomes.
    # `--delete-backup-data true` moves an item to a soft-deleted state that
    # the list API keeps returning for 14 days, and neither the vault delete
    # nor the group delete is blocked by items in that state: Azure permits
    # deleting a vault that is empty "or has only soft-deleted backup items or
    # containers". Polling for length 0 would burn the full timeout and then
    # print a warning about a situation that is fine.
    echo ">>> Waiting for protection to stop on every item (up to 5 min)..."
    STILL_ACTIVE=1
    for _ in $(seq 1 30); do
      STILL_ACTIVE=0
      for BMT in "${BACKUP_TYPES[@]}"; do
        ACTIVE_OF_TYPE=$(az backup item list --resource-group "$RESOURCE_GROUP" --vault-name "$VAULT" \
          --backup-management-type "$BMT" \
          --query "[?properties.isScheduledForDeferredDelete != \`true\` && properties.protectionState != 'ProtectionStopped'] | length(@)" \
          -o tsv 2>/dev/null || echo "0")
        # Strip to digits before the arithmetic. Anything else the CLI puts on
        # stdout would be evaluated as a variable name in $(( )) and, under
        # set -u, abort the script here — before the vault and the group are
        # deleted, which is the one outcome this script must never produce.
        ACTIVE_OF_TYPE=${ACTIVE_OF_TYPE//[^0-9]/}
        STILL_ACTIVE=$((STILL_ACTIVE + ${ACTIVE_OF_TYPE:-0}))
      done
      if [[ "$STILL_ACTIVE" == "0" ]]; then
        break
      fi
      sleep 10
    done
    if [[ "$STILL_ACTIVE" == "0" ]]; then
      echo ">>> No item is actively protected. Any items still listed are soft-deleted,"
      echo "    which does not block the deletes below and clears itself in 14 days."
    else
      echo "WARNING: ${STILL_ACTIVE} item(s) are still actively protected; the group delete may fail." >&2
    fi
  fi

  # ---- 2. delete the vault, cascading anything left ---------------------------
  echo ">>> Deleting vault ${VAULT}..."
  az backup vault delete --resource-group "$RESOURCE_GROUP" --name "$VAULT" --force --yes --output none ||
    echo "WARNING: vault delete reported an error; the group delete below will say if it mattered." >&2
else
  echo ">>> No recovery services vault in ${RESOURCE_GROUP}."
fi

# ---- 3. the resource group ----------------------------------------------------
echo ">>> Deleting ${RESOURCE_GROUP} (this takes several minutes)..."
az group delete --name "$RESOURCE_GROUP" --yes

# ---- 4. verify ----------------------------------------------------------------
if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "FATAL: ${RESOURCE_GROUP} still exists after delete — investigate before re-running." >&2
  echo "If the error mentioned existing resources within the vault, an item survived step 1." >&2
  echo "Ask each backup management type in turn — the list call answers for one at a time:" >&2
  for BMT in AzureIaasVM AzureWorkload AzureStorage; do
    echo "  az backup item list --resource-group ${RESOURCE_GROUP} --vault-name <vault> --backup-management-type ${BMT} -o table" >&2
  done
  exit 1
fi

# Local state now describes resources that no longer exist; clearing it keeps
# the next deploy.sh from trying to reconcile them.
rm -f "${TF_DIR}/terraform.tfstate" "${TF_DIR}/terraform.tfstate.backup"

echo ""
echo "azure/j5-vmss-sql-iaas teardown complete — ${RESOURCE_GROUP} is gone."
echo ""
echo "Two things outlive the group. Neither bills and neither needs a hand:"
echo "  * the backup items disabled above are soft-deleted for 14 days and cannot be purged early"
echo "  * the SQL VM's instant-restore snapshots sit in a service-owned resource group named"
echo "    AzureBackupRG_<geo>_<n>, outside ${RESOURCE_GROUP} and carrying none of its tags, so a"
echo "    tag-filtered sweep will not list them. They expire on the policy's snapshot retention"
echo "    (two days by default) and are collected within about a day of expiring. Leave them."
