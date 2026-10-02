#!/usr/bin/env bash
# seed.sh — load the notice board and publish the registrar's documents.
# -----------------------------------------------------------------------------
# Run this once after deploy.sh. It is idempotent: the table is created only if
# it is missing, its contents are replaced wholesale from
# app/seed-data/notices.json, and the document upload overwrites.
#
# Neither credential is generated here. Both are read back out of what deploy.sh
# created — the SQL login and password out of the site's PortalDb connection
# string, and the storage account key out of the account — so this script needs
# no more than Contributor on the resource group and holds no secret of its own.
#
# One grant is needed and it is temporary: the SQL logical server's firewall
# admits Azure services, which covers the App Service workers, but not this
# machine. A rule for the operator's address is added on the way in and removed
# on the way out.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   SEED_CLIENT_IP             this machine's public IPv4, for the firewall rule.
#                              CPI_SEED_CLIENT_IP overrides it for this journey.
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
RESOURCE_GROUP="cpi-rg"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi

# The operator's own address. It is a property of the machine rather than of
# this estate, so the shared name is the one to set; the prefixed name is here
# for a run that needs to override it.
SEED_CLIENT_IP="${CPI_SEED_CLIENT_IP:-${SEED_CLIENT_IP:-}}"
: "${SEED_CLIENT_IP:?Set SEED_CLIENT_IP=<this machine public IPv4> in ~/.azure/journeys.env}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/../app"

# ---- discover what deploy.sh created ------------------------------------------
WEB_APP_NAME=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
SQL_SERVER_NAME=$(az sql server list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)
STORAGE_ACCOUNT=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)

if [[ -z "$WEB_APP_NAME" || -z "$SQL_SERVER_NAME" || -z "$STORAGE_ACCOUNT" ]]; then
  echo "FATAL: ${RESOURCE_GROUP} is not fully deployed — run ./scripts/deploy.sh first." >&2
  exit 1
fi
echo "Seeding azure/j8-clickops-partial-iac: ${WEB_APP_NAME} / ${SQL_SERVER_NAME} / ${STORAGE_ACCOUNT}"

# ---- database credentials, read back rather than re-generated -----------------
# deploy.sh generates the SQL password and throws it away. The site's connection
# strings collection is the only place it survives. Handing it to Python through
# the environment keeps it out of argv and out of the process table.
export PORTAL_DB_CONNECTION
PORTAL_DB_CONNECTION=$(az webapp config connection-string list \
  --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" \
  --query "[?name=='PortalDb'].value | [0]" -o tsv)

if [[ -z "$PORTAL_DB_CONNECTION" ]]; then
  echo "FATAL: ${WEB_APP_NAME} has no PortalDb connection string — re-run ./scripts/deploy.sh." >&2
  exit 1
fi

# ---- temporary firewall opening for this machine ------------------------------
# Azure offers no first-party "what address am I calling from" endpoint, and this
# script will not call a third-party one, so the operator supplies it. If it is
# wrong, the server says so: a blocked connection is refused with a message
# naming the address it saw.
FIREWALL_RULE="seed-$(date -u +%Y%m%d%H%M%S)"

cleanup() {
  echo ">>> Removing temporary firewall rule ${FIREWALL_RULE}"
  az sql server firewall-rule delete \
    --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" \
    --name "$FIREWALL_RULE" --output none 2>/dev/null || true
}
trap cleanup EXIT

echo ">>> Opening ${SQL_SERVER_NAME} to ${SEED_CLIENT_IP} as ${FIREWALL_RULE}"
az sql server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER_NAME" \
  --name "$FIREWALL_RULE" \
  --start-ip-address "$SEED_CLIENT_IP" --end-ip-address "$SEED_CLIENT_IP" \
  --output none

# ---- notice board --------------------------------------------------------------
VENV_DIR="${APP_DIR}/.venv"
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo ">>> Creating a local virtual environment for the loader"
  python3 -m venv "$VENV_DIR"
fi
"${VENV_DIR}/bin/pip" install --quiet --disable-pip-version-check -r "${APP_DIR}/requirements.txt"

echo ">>> Loading the notice board"
NOTICE_COUNT=$(PYTHONPATH="$APP_DIR" "${VENV_DIR}/bin/python" - "${APP_DIR}/seed-data/notices.json" <<'PY'
import json
import os
import sys

import pymssql

# The same parser the running site uses, so a string the site cannot read is a
# string this loader cannot read either.
from portal.azure_clients import parse_sql_connection_string

settings = parse_sql_connection_string(os.environ["PORTAL_DB_CONNECTION"])
if not settings:
    sys.exit("FATAL: the PortalDb connection string names no server.")

# The loader waits longer than the site does: a database that has just been
# created can take a moment to accept its first session.
settings["login_timeout"] = 30
settings["timeout"] = 60

with open(sys.argv[1], encoding="utf-8") as handle:
    notices = json.load(handle)

rows = [
    (n["id"], n["posted_on"], n["category"], n["title"], n["body"]) for n in notices
]

connection = pymssql.connect(**settings)
with connection:
    cursor = connection.cursor()
    cursor.execute(
        """
        IF OBJECT_ID('dbo.notices', 'U') IS NULL
        CREATE TABLE dbo.notices (
            id        INT           NOT NULL PRIMARY KEY,
            posted_on DATE          NOT NULL,
            category  NVARCHAR(40)  NOT NULL,
            title     NVARCHAR(200) NOT NULL,
            body      NVARCHAR(MAX) NOT NULL
        )
        """
    )
    cursor.execute("DELETE FROM dbo.notices")
    cursor.executemany(
        "INSERT INTO dbo.notices (id, posted_on, category, title, body)"
        " VALUES (%d, %s, %s, %s, %s)",
        rows,
    )
    connection.commit()
    cursor.execute("SELECT COUNT(*) FROM dbo.notices")
    (count,) = cursor.fetchone()
print(count)
PY
)
echo "    notice board holds ${NOTICE_COUNT} notices"

# ---- document library -----------------------------------------------------------
# The account key goes into the environment the CLI already reads, not onto a
# command line.
echo ">>> Publishing the registrar's documents"
export AZURE_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
export AZURE_STORAGE_KEY
AZURE_STORAGE_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" --account-name "$STORAGE_ACCOUNT" \
  --query "[0].value" -o tsv)

az storage blob upload-batch \
  --auth-mode key \
  --destination "documents" \
  --source "${APP_DIR}/seed-data/documents" \
  --pattern "*.txt" \
  --content-type "text/plain; charset=utf-8" \
  --overwrite \
  --output none

DOCUMENT_COUNT=$(az storage blob list --auth-mode key --container-name "documents" \
  --query "length(@)" -o tsv)

# ---- restart so the workers pick up a warm database -----------------------------
echo ">>> Restarting ${WEB_APP_NAME}"
az webapp restart --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --output none

echo ""
echo "============================================================"
echo ">>> Seeded. ${NOTICE_COUNT} notices on the board, ${DOCUMENT_COUNT} documents published."
echo "Verify with:"
echo "  ./scripts/smoke-test.sh <BASE_URL>"
echo "============================================================"
