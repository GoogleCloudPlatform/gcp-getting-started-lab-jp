#!/usr/bin/env bash
# 03-secrets.sh — Secret Manager entries, same names and payload shapes as the
# AWS side:
#
#   ttw-db-password     {"username":"shop","password":"<generated>"}
#                       Generated here at deploy time (never written to disk,
#                       piped straight into the secret version). If a version
#                       already exists it is left alone, so re-runs never
#                       rotate the password out from under Cloud SQL.
#   ttw-legacy-api-key  {"api_key":"PLACEHOLDER_OVERWRITE_AFTER_DEPLOY"}
#                       Same placeholder semantics as the journey: the app
#                       only ever reads the secret's METADATA.
#
# Grants (per secret, to ttw-app-sa):
#   roles/secretmanager.secretAccessor  read versions (DB creds fetch)
#   roles/secretmanager.viewer          read metadata (the status ping —
#                                       accessor alone cannot get_secret)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

ensure_secret() {
  local name="$1"
  if ! gcloud secrets describe "$name" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
    gcloud secrets create "$name" \
      --project "${GCP_PROJECT}" \
      --replication-policy=user-managed \
      --locations="${GCP_REGION}" \
      --labels=journey=j2-three-tier-web,owner=migration-test
  else
    echo "Secret $name already exists."
  fi
}

has_version() {
  local name="$1"
  [[ -n "$(gcloud secrets versions list "$name" --project "${GCP_PROJECT}" \
            --filter='state=enabled' --format='value(name)' --limit=1)" ]]
}

grant() {
  local name="$1" role="$2"
  gcloud secrets add-iam-policy-binding "$name" \
    --project "${GCP_PROJECT}" \
    --member "serviceAccount:${SA_EMAIL}" \
    --role "$role" >/dev/null
}

# ---- ttw-db-password -----------------------------------------------------------
ensure_secret "${SECRET_DB}"
if has_version "${SECRET_DB}"; then
  echo "${SECRET_DB} already has a version — keeping the existing password."
else
  PASSWORD="$(openssl rand -hex 16)"   # 32 alnum chars: JSON- and psql-safe
  printf '{"username":"%s","password":"%s"}' "${DB_USER}" "${PASSWORD}" \
    | gcloud secrets versions add "${SECRET_DB}" --project "${GCP_PROJECT}" --data-file=-
  echo "Added generated credentials version to ${SECRET_DB}."
fi
grant "${SECRET_DB}" roles/secretmanager.secretAccessor
grant "${SECRET_DB}" roles/secretmanager.viewer

# ---- ttw-legacy-api-key ----------------------------------------------------------
ensure_secret "${SECRET_LEGACY}"
if has_version "${SECRET_LEGACY}"; then
  echo "${SECRET_LEGACY} already has a version — leaving it."
else
  printf '{"api_key":"PLACEHOLDER_OVERWRITE_AFTER_DEPLOY"}' \
    | gcloud secrets versions add "${SECRET_LEGACY}" --project "${GCP_PROJECT}" --data-file=-
  echo "Added placeholder version to ${SECRET_LEGACY} (parity with the AWS trap)."
fi
grant "${SECRET_LEGACY}" roles/secretmanager.secretAccessor
grant "${SECRET_LEGACY}" roles/secretmanager.viewer

echo "Secrets ready."
