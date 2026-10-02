#!/usr/bin/env bash
# 02-knowledge-base.sh — Cloud SQL PostgreSQL 16 + the connection secret
# (idempotent, describe-or-create).
#
# Connectivity is DEMO-GRADE on purpose: public IP, 0.0.0.0/0 authorized
# networks, TLS required, password auth, fixture data only. Agent Runtime
# publishes no fixed egress range; a production estate reaches Cloud SQL
# through the Cloud SQL connectors or PSC — hardening the skill's runbook
# schedules right after the lift.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/00-env.sh"

if ! gcloud sql instances describe "${KB_INSTANCE}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo ">>> Creating Cloud SQL ${KB_INSTANCE} (PG16, db-f1-micro, ~10 min)"
  gcloud sql instances create "${KB_INSTANCE}" --project "${GCP_PROJECT}" \
    --database-version=POSTGRES_16 --edition=enterprise --tier=db-f1-micro \
    --region="${REGION}" --authorized-networks=0.0.0.0/0 --ssl-mode=ENCRYPTED_ONLY \
    --root-password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 28)"
else
  echo ">>> ${KB_INSTANCE} exists"
fi

KB_HOST="$(gcloud sql instances describe "${KB_INSTANCE}" --project "${GCP_PROJECT}" \
  --format='value(ipAddresses[0].ipAddress)')"

gcloud sql databases describe "${KB_DATABASE}" --instance="${KB_INSTANCE}" \
  --project "${GCP_PROJECT}" >/dev/null 2>&1 ||
  gcloud sql databases create "${KB_DATABASE}" --instance="${KB_INSTANCE}" --project "${GCP_PROJECT}"

PASS_FILE="${HOME}/.config/arc-reference.dbpass"
[[ -f "${PASS_FILE}" ]] || (umask 177 && openssl rand -base64 24 | tr -d '/+=' | head -c 28 > "${PASS_FILE}")
KB_PASS="$(cat "${PASS_FILE}")"

gcloud sql users create "${KB_USER}" --instance="${KB_INSTANCE}" \
  --project "${GCP_PROJECT}" --password="${KB_PASS}" 2>/dev/null ||
  gcloud sql users set-password "${KB_USER}" --instance="${KB_INSTANCE}" \
    --project "${GCP_PROJECT}" --password="${KB_PASS}"

PAYLOAD="$(printf '{"host":"%s","port":5432,"user":"%s","password":"%s","dbname":"%s"}' \
  "${KB_HOST}" "${KB_USER}" "${KB_PASS}" "${KB_DATABASE}")"
if gcloud secrets describe "${KB_SECRET}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  printf '%s' "${PAYLOAD}" | gcloud secrets versions add "${KB_SECRET}" --project "${GCP_PROJECT}" --data-file=-
else
  printf '%s' "${PAYLOAD}" | gcloud secrets create "${KB_SECRET}" --project "${GCP_PROJECT}" --data-file=-
fi

gcloud secrets add-iam-policy-binding "${KB_SECRET}" --project "${GCP_PROJECT}" \
  --member="serviceAccount:${RUNTIME_SA}" --role="roles/secretmanager.secretAccessor" >/dev/null
echo ">>> ${KB_SECRET} readable by ${RUNTIME_SA}; instance at ${KB_HOST}"
