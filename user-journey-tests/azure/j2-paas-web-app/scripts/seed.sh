#!/usr/bin/env bash
# seed.sh — load the stationery shop's catalogue into PostgreSQL and push the
# product images into blob storage.
# -----------------------------------------------------------------------------
# Run this once after deploy.sh. It is idempotent: the migration is a no-op on a
# second run, `loaddata` upserts on the fixed primary keys in
# app/seed-data/catalogue.json, and the image upload overwrites.
#
# Two grants are needed and both are attempted here rather than in the template,
# because they are about the operator running this script, not about the running
# application:
#   * a PostgreSQL firewall rule for this machine's public address, removed again
#     on exit;
#   * Storage Blob Data Contributor on the media container for the signed-in
#     principal, so images upload over Entra ID rather than an account key. The
#     storage account has shared-key access switched off, so there is no key to
#     use even if we wanted one.
#
# The second one is privileged: writing a role assignment needs Owner or User
# Access Administrator, so on a Contributor-only subscription it is refused. That
# is reported loudly and the run continues; the catalogue still loads and the
# shop still serves, but the media container stays empty and this script exits
# nonzero so a partial seed cannot be mistaken for a whole one.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   SEED_CLIENT_IP             this machine's public IPv4, for the firewall rule
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
RESOURCE_GROUP="pwa-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/../app"

# ---- discover what deploy.sh created ------------------------------------------
WEB_APP_NAME=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
POSTGRES_NAME=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv)
STORAGE_ACCOUNT=$(az storage account list --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" -o tsv)

if [[ -z "$WEB_APP_NAME" || -z "$POSTGRES_NAME" || -z "$STORAGE_ACCOUNT" ]]; then
  echo "FATAL: ${RESOURCE_GROUP} is not fully deployed — run ./scripts/deploy.sh first." >&2
  exit 1
fi
echo "Seeding azure/j2-paas-web-app: ${WEB_APP_NAME} / ${POSTGRES_NAME} / ${STORAGE_ACCOUNT}"

# ---- connection settings, read back from the app rather than re-generated -----
# deploy.sh generates the database password and throws it away. The app settings
# are the only place it survives, and reading them keeps it out of argv.
read_setting() {
  az webapp config appsettings list \
    --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" \
    --query "[?name=='${1}'].value | [0]" -o tsv
}

export PWA_DB_HOST
export PWA_DB_NAME
export PWA_DB_USER
export PWA_DB_PASSWORD
export PWA_DB_SSLMODE
PWA_DB_HOST="$(read_setting PWA_DB_HOST)"
PWA_DB_NAME="$(read_setting PWA_DB_NAME)"
PWA_DB_USER="$(read_setting PWA_DB_USER)"
PWA_DB_PASSWORD="$(read_setting PWA_DB_PASSWORD)"
PWA_DB_SSLMODE="require"

if [[ -z "$PWA_DB_PASSWORD" ]]; then
  echo "FATAL: could not read PWA_DB_PASSWORD from ${WEB_APP_NAME}'s app settings." >&2
  exit 1
fi

# ---- temporary firewall opening for this machine ------------------------------
# Azure offers no first-party "what address am I calling from" endpoint, and this
# script will not call a third-party one, so the operator supplies it. If it is
# wrong, the server says so: a blocked connection is refused with a message
# naming the address it saw.
: "${SEED_CLIENT_IP:?Set SEED_CLIENT_IP=<this machine public IPv4> in ~/.azure/journeys.env}"
FIREWALL_RULE="seed-$(date -u +%Y%m%d%H%M%S)"

cleanup() {
  echo ">>> Removing temporary firewall rule ${FIREWALL_RULE}"
  az postgres flexible-server firewall-rule delete \
    --resource-group "$RESOURCE_GROUP" --server-name "$POSTGRES_NAME" \
    --name "$FIREWALL_RULE" --yes --output none 2>/dev/null || true
}
trap cleanup EXIT

echo ">>> Opening ${POSTGRES_NAME} to ${SEED_CLIENT_IP} as ${FIREWALL_RULE}"
az postgres flexible-server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" --server-name "$POSTGRES_NAME" \
  --name "$FIREWALL_RULE" \
  --start-ip-address "$SEED_CLIENT_IP" --end-ip-address "$SEED_CLIENT_IP" \
  --output none

# ---- schema and catalogue -----------------------------------------------------
VENV_DIR="${APP_DIR}/.venv"
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo ">>> Creating a local virtual environment for the management commands"
  python3 -m venv "$VENV_DIR"
fi
"${VENV_DIR}/bin/pip" install --quiet --disable-pip-version-check -r "${APP_DIR}/requirements.txt"

echo ">>> Applying migrations"
(cd "$APP_DIR" && "${VENV_DIR}/bin/python" manage.py migrate --noinput)

echo ">>> Loading the catalogue"
(cd "$APP_DIR" && "${VENV_DIR}/bin/python" manage.py loaddata seed-data/catalogue.json)

# ---- product images -----------------------------------------------------------
# Uploading over Entra ID needs Storage Blob Data Contributor on the container.
# Granting it is itself a privileged write: creating any role assignment needs
# Owner or User Access Administrator on the scope, which Contributor is not. On
# a subscription where this account is only Contributor the grant is refused,
# and there is no way around it from here — the storage account has shared-key
# access switched off, so there is no account key to fall back to, and a
# user-delegation SAS would need the same blob data permission we are missing.
# So: try, say plainly what happened, and carry on without the images rather
# than pretending.
CONTAINER_SCOPE=$(az storage account show \
  --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT" --query id -o tsv)
CONTAINER_SCOPE="${CONTAINER_SCOPE}/blobServices/default/containers/media"
CALLER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")

GRANT_STATE="not attempted"
if [[ -n "$CALLER_OBJECT_ID" ]]; then
  echo ">>> Granting Storage Blob Data Contributor on the media container to the signed-in user"
  if GRANT_ERR=$(az role assignment create \
    --assignee-object-id "$CALLER_OBJECT_ID" \
    --assignee-principal-type User \
    --role "Storage Blob Data Contributor" \
    --scope "$CONTAINER_SCOPE" \
    --output none 2>&1); then
    GRANT_STATE="created"
    echo "    waiting 30s for the role assignment to propagate"
    sleep 30
  elif grep -qiE "RoleAssignmentExists|already exists" <<<"$GRANT_ERR"; then
    GRANT_STATE="already present"
    echo "    already granted"
  else
    GRANT_STATE="REFUSED"
    echo "    !! the role assignment was REFUSED:" >&2
    head -3 <<<"$GRANT_ERR" | sed 's/^/       /' >&2
    echo "    Creating a role assignment needs Owner or User Access Administrator on" >&2
    echo "    the scope. Contributor cannot do it, and this account appears to be" >&2
    echo "    Contributor. Continuing: the upload below succeeds only if this" >&2
    echo "    principal already holds blob data access some other way." >&2
  fi
else
  GRANT_STATE="no signed-in user (service principal?)"
  echo "    could not resolve the signed-in principal; not attempting a grant"
fi

echo ">>> Uploading product images"
IMAGES_SEEDED=0
if UPLOAD_ERR=$(az storage blob upload-batch \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login \
  --destination "media" \
  --source "${APP_DIR}/seed-data/media" \
  --pattern "*.svg" \
  --content-type "image/svg+xml" \
  --overwrite \
  --output none 2>&1); then
  IMAGES_SEEDED=1
  echo "    six images uploaded"
else
  echo "    !! the image upload FAILED:" >&2
  head -5 <<<"$UPLOAD_ERR" | sed 's/^/       /' >&2
fi

# ---- restart so the workers pick up a warm database ---------------------------
echo ">>> Restarting ${WEB_APP_NAME}"
az webapp restart --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --output none

echo ""
echo "============================================================"
echo ">>> Seed report for ${RESOURCE_GROUP}"
echo "    catalogue      six products across three categories, loaded"
echo "    blob data role ${GRANT_STATE}"
if [[ "$IMAGES_SEEDED" -eq 1 ]]; then
  echo "    images         six uploaded to the media container"
  echo ""
  echo "Verify with:"
  echo "  ./scripts/smoke-test.sh <BASE_URL>"
  echo "============================================================"
else
  echo "    images         NOT UPLOADED — the media container is empty"
  echo ""
  echo "The shop will serve, and every catalogue and product page will render,"
  echo "but product images will 404. Have someone with Owner or User Access"
  echo "Administrator grant Storage Blob Data Contributor on"
  echo "  ${CONTAINER_SCOPE}"
  echo "to this principal, then re-run this script — it is idempotent."
  echo "============================================================"
  exit 1
fi
