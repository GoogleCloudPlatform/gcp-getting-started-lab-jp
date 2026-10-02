#!/usr/bin/env bash
# 99-teardown.sh — destroy every j2-three-tier-web GCP reference resource,
# strictly LB-first (reverse of 01-09). Confirmation-gated: type "yes" at the
# prompt, or set FORCE_TEARDOWN=1 for non-interactive runs.
#
# Each delete is skipped cleanly when the resource is already gone, so the
# script is safe to re-run after a partial teardown.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  echo "About to DESTROY all j2-three-tier-web reference resources in project ${GCP_PROJECT}."
  read -r -p 'Type "yes" to continue: ' CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted (nothing destroyed)."
    exit 1
  fi
fi

# ---- LB path (reverse of 09) ---------------------------------------------------
if gcloud compute forwarding-rules describe "${FWD_RULE}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute forwarding-rules delete "${FWD_RULE}" --global --project "${GCP_PROJECT}" --quiet
else echo ">>> forwarding rule ${FWD_RULE} not found — skipping."; fi

if gcloud compute target-http-proxies describe "${PROXY_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute target-http-proxies delete "${PROXY_NAME}" --global --project "${GCP_PROJECT}" --quiet
else echo ">>> target proxy ${PROXY_NAME} not found — skipping."; fi

if gcloud compute url-maps describe "${URLMAP_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute url-maps delete "${URLMAP_NAME}" --global --project "${GCP_PROJECT}" --quiet
else echo ">>> url map ${URLMAP_NAME} not found — skipping."; fi

if gcloud compute backend-services describe "${BACKEND_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute backend-services delete "${BACKEND_NAME}" --global --project "${GCP_PROJECT}" --quiet
else echo ">>> backend service ${BACKEND_NAME} not found — skipping."; fi

if gcloud compute health-checks describe "${HC_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute health-checks delete "${HC_NAME}" --global --project "${GCP_PROJECT}" --quiet
else echo ">>> health check ${HC_NAME} not found — skipping."; fi

if gcloud compute addresses describe "${LB_IP_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute addresses delete "${LB_IP_NAME}" --global --project "${GCP_PROJECT}" --quiet
else echo ">>> address ${LB_IP_NAME} not found — skipping."; fi

# ---- MIG + template (reverse of 08) -----------------------------------------------
if gcloud compute instance-groups managed describe "${MIG_NAME}" --zone "${GCP_ZONE}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo ">>> Deleting MIG ${MIG_NAME} (waits for instances)"
  gcloud compute instance-groups managed delete "${MIG_NAME}" --zone "${GCP_ZONE}" --project "${GCP_PROJECT}" --quiet
else echo ">>> MIG ${MIG_NAME} not found — skipping."; fi

if gcloud compute instance-templates describe "${TEMPLATE_NAME}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute instance-templates delete "${TEMPLATE_NAME}" --project "${GCP_PROJECT}" --quiet
else echo ">>> template ${TEMPLATE_NAME} not found — skipping."; fi

# ---- firewall (reverse of 07) --------------------------------------------------------
for rule in "${FW_HEALTH}" "${FW_LB}"; do
  if gcloud compute firewall-rules describe "$rule" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
    gcloud compute firewall-rules delete "$rule" --project "${GCP_PROJECT}" --quiet
  else echo ">>> firewall rule $rule not found — skipping."; fi
done

# ---- bucket (reverse of 05/06): empty it first ------------------------------------------
if gcloud storage buckets describe "gs://${BUCKET_NAME}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo ">>> Emptying and deleting gs://${BUCKET_NAME}"
  gcloud storage rm -r "gs://${BUCKET_NAME}/**" --project "${GCP_PROJECT}" 2>/dev/null || true
  gcloud storage buckets delete "gs://${BUCKET_NAME}" --project "${GCP_PROJECT}" --quiet
else echo ">>> bucket gs://${BUCKET_NAME} not found — skipping."; fi

# ---- Cloud SQL (reverse of 04) -------------------------------------------------------------
if gcloud sql instances describe "${SQL_INSTANCE}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  echo ">>> Deleting Cloud SQL instance ${SQL_INSTANCE} (takes a few minutes)"
  gcloud sql instances delete "${SQL_INSTANCE}" --project "${GCP_PROJECT}" --quiet
else echo ">>> Cloud SQL instance ${SQL_INSTANCE} not found — skipping."; fi

# ---- secrets (reverse of 03) -----------------------------------------------------------------
for secret in "${SECRET_DB}" "${SECRET_LEGACY}"; do
  if gcloud secrets describe "$secret" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
    gcloud secrets delete "$secret" --project "${GCP_PROJECT}" --quiet
  else echo ">>> secret $secret not found — skipping."; fi
done

# ---- service account (reverse of 02) ------------------------------------------------------------
if gcloud iam service-accounts describe "${SA_EMAIL}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud iam service-accounts delete "${SA_EMAIL}" --project "${GCP_PROJECT}" --quiet
else echo ">>> service account ${SA_EMAIL} not found — skipping."; fi

echo ""
echo "j2-three-tier-web GCP reference teardown complete."
