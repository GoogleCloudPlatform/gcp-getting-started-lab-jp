#!/usr/bin/env bash
# 04-sql.sh — Cloud SQL for PostgreSQL (the RDS ttw-postgres analogue).
#
#   instance ttw-postgres   POSTGRES_16, tier db-g1-small in asia-northeast1
#                           (verified 2026-07), 20 GB SSD, zonal, no deletion
#                           protection — first create takes ~10-15 minutes.
#   database online_shop
#   user     shop         password read back from Secret Manager (03), so
#                           the app and the DB always agree.
#
# Apps never dial the instance address: every VM runs a Cloud SQL Auth Proxy
# sidecar on 127.0.0.1:5432 (see startup-script.sh), authenticated as
# ttw-app-sa via roles/cloudsql.client.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

# ---- instance --------------------------------------------------------------------
if ! gcloud sql instances describe "${SQL_INSTANCE}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo ">>> Creating Cloud SQL instance ${SQL_INSTANCE} (~10-15 minutes)"
  gcloud sql instances create "${SQL_INSTANCE}" \
    --project "${GCP_PROJECT}" \
    --database-version=POSTGRES_16 \
    --edition=enterprise \
    --tier=db-g1-small \
    --region="${GCP_REGION}" \
    --storage-type=SSD \
    --storage-size=20GB \
    --availability-type=zonal
else
  echo "Cloud SQL instance ${SQL_INSTANCE} already exists."
fi

# ---- database ---------------------------------------------------------------------
if ! gcloud sql databases describe "${DB_NAME}" --instance "${SQL_INSTANCE}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud sql databases create "${DB_NAME}" --instance "${SQL_INSTANCE}" --project "${GCP_PROJECT}"
else
  echo "Database ${DB_NAME} already exists."
fi

# ---- user -------------------------------------------------------------------------
# Password comes from the secret created in 03 — read into a variable only,
# never onto disk. set-password keeps re-runs idempotent AND heals any drift
# between the secret and the DB user.
DB_PASSWORD="$(gcloud secrets versions access latest --secret "${SECRET_DB}" --project "${GCP_PROJECT}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"

if gcloud sql users list --instance "${SQL_INSTANCE}" --project "${GCP_PROJECT}" \
     --format='value(name)' | grep -qx "${DB_USER}"; then
  gcloud sql users set-password "${DB_USER}" \
    --instance "${SQL_INSTANCE}" --project "${GCP_PROJECT}" --password "${DB_PASSWORD}"
  echo "User ${DB_USER} exists — password re-synced from ${SECRET_DB}."
else
  gcloud sql users create "${DB_USER}" \
    --instance "${SQL_INSTANCE}" --project "${GCP_PROJECT}" --password "${DB_PASSWORD}"
  echo "User ${DB_USER} created."
fi

echo "Cloud SQL ready: ${SQL_CONNECTION}"
