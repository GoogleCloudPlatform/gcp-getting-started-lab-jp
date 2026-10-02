#!/usr/bin/env bash
# seed.sh — load the fund documentation and build the search index.
# -----------------------------------------------------------------------------
# Run this once after deploy.sh. It is idempotent: the upload overwrites, the
# index create is a create-or-update, and the document push upserts on the fixed
# document ids.
#
# Two halves, because the two services are reachable from different places:
#
#   1. The markdown notes in app/seed-data/docs go into blob storage from THIS
#      machine. The storage account answers over its public endpoint, so that
#      works from anywhere.
#   2. The index is then built by the APP, through POST /admin/reindex. The
#      search service only answers on its private endpoint inside car-vnet, so
#      this machine cannot reach it at all — the container app is the only thing
#      that can, and it is also the only thing holding the two search roles.
#
# One grant is made here rather than in the template, because it is about the
# operator running this script and not about the running application: Storage
# Blob Data Contributor on the documentation container for the signed-in
# principal, so the notes upload over Entra ID. The storage account has
# shared-key access switched off, so there is no account key to fall back on.
# Creating that grant needs more than Contributor on the scope; where the
# signed-in principal does not have it, the grant is skipped and the upload
# fails with a message naming the role.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
# -----------------------------------------------------------------------------

set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCS_DIR="${SCRIPT_DIR}/../app/seed-data/docs"

STORAGE_ACCOUNT=$(az storage account list --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")
CONTAINER_APP=$(az containerapp list --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")

if [[ -z "$STORAGE_ACCOUNT" || -z "$CONTAINER_APP" ]]; then
  echo "FATAL: ${RESOURCE_GROUP} is not fully deployed — run ./scripts/deploy.sh first." >&2
  exit 1
fi

BASE_URL="https://$(az containerapp show --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" --query "properties.configuration.ingress.fqdn" -o tsv)"

echo "Seeding azure/j7-container-apps-rag: ${STORAGE_ACCOUNT} -> ${CONTAINER_APP}"

# ---- 1. the corpus -----------------------------------------------------------
CONTAINER_SCOPE=$(az storage account show --resource-group "$RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT" --query id -o tsv)/blobServices/default/containers/docs

CALLER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")

if [[ -n "$CALLER_OBJECT_ID" ]]; then
  echo ">>> Granting Storage Blob Data Contributor on the docs container to the signed-in user"
  if az role assignment create \
    --assignee-object-id "$CALLER_OBJECT_ID" \
    --assignee-principal-type User \
    --role "Storage Blob Data Contributor" \
    --scope "$CONTAINER_SCOPE" \
    --output none 2>/dev/null; then
    echo "    created — it takes a few minutes to become usable"
  else
    echo "    not created — either it is already there, or the signed-in principal"
    echo "    cannot write role assignments on this scope. If the upload below"
    echo "    never succeeds, that is the reason, and Storage Blob Data Contributor"
    echo "    on ${STORAGE_ACCOUNT} is what is missing."
  fi
else
  echo "    could not resolve the signed-in principal; assuming blob data access is already granted"
fi

# Role assignments take up to five minutes to become usable, and the container
# app's own five grants were created seconds ago by deploy.sh. Everything from
# here to the end of the script retries rather than failing on the first try,
# because the overwhelmingly common first-run failure is propagation delay and
# not a real misconfiguration.
ATTEMPTS=8
DELAY=30

echo ">>> Uploading fund documentation"
for attempt in $(seq 1 "$ATTEMPTS"); do
  if az storage blob upload-batch \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --destination "docs" \
    --source "$DOCS_DIR" \
    --pattern "*.md" \
    --content-type "text/markdown" \
    --overwrite \
    --output none 2>/dev/null; then
    break
  fi
  if [[ "$attempt" -eq "$ATTEMPTS" ]]; then
    echo "FATAL: could not upload after ${ATTEMPTS} attempts over $((ATTEMPTS * DELAY))s." >&2
    echo "  The signed-in principal needs Storage Blob Data Contributor on" >&2
    echo "  ${STORAGE_ACCOUNT}. Shared-key access is switched off on the account," >&2
    echo "  so there is no key to fall back on. Ask a subscription administrator" >&2
    echo "  for the grant and re-run this script." >&2
    exit 1
  fi
  echo "    attempt ${attempt}/${ATTEMPTS} failed, retrying in ${DELAY}s (role assignments propagate slowly)"
  sleep "$DELAY"
done

UPLOADED=$(az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login \
  --container-name "docs" \
  --query "length(@)" -o tsv)
echo "    ${UPLOADED} document(s) in the container"

# ---- 2. the index ------------------------------------------------------------
# The first call also wakes a scaled-to-zero app, so allow for a cold start.
echo ""
echo ">>> Asking ${CONTAINER_APP} to rebuild the index (it is the only thing that can reach the search service)"
echo "    the first call also wakes a scaled-to-zero replica"
REINDEX=""
for attempt in $(seq 1 "$ATTEMPTS"); do
  REINDEX=$(curl -sS --max-time 180 -X POST "${BASE_URL}/admin/reindex" 2>/dev/null || echo "")
  echo "    attempt ${attempt}/${ATTEMPTS}: ${REINDEX:-<no response>}"
  if grep -q '"documents_indexed": *[1-9]' <<<"$REINDEX"; then
    break
  fi
  if [[ "$attempt" -eq "$ATTEMPTS" ]]; then
    echo "" >&2
    echo "FATAL: no documents made it into the index after ${ATTEMPTS} attempts." >&2
    echo "  This is no longer propagation delay. Check, in this order:" >&2
    echo "  1. curl ${BASE_URL}/admin/azure-check   — are search and blob_storage ok?" >&2
    echo "  2. does the container app's identity hold Search Service Contributor AND" >&2
    echo "     Search Index Data Contributor? Without both, the index is created but" >&2
    echo "     stays empty, or is never created at all. Both sit behind the" >&2
    echo "     deployRoleAssignments parameter." >&2
    echo "  3. is the private DNS zone privatelink.search.windows.net linked to car-vnet?" >&2
    exit 1
  fi
  sleep "$DELAY"
done

echo ""
echo "============================================================"
echo ">>> Seeded. ${UPLOADED} fund note(s) uploaded and indexed."
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo "============================================================"
