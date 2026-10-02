#!/usr/bin/env bash
# deploy.sh — deploy the azure/j5-vmss-sql-iaas test bed (the precision-parts
# MES operator, vsi-*) to Azure.
# -----------------------------------------------------------------------------
# Idempotent: `terraform apply` converges. One caveat — the local Windows
# administrator password is regenerated on every run, so a re-deploy rotates it
# on the scale set model and on the database server. It is never written to
# this repository and never printed.
#
# Everything lands in ONE resource group (vsi-rg) so teardown is a single
# `az group delete` once the vault has been emptied. See scripts/teardown.sh:
# a Recovery Services vault holding backup data BLOCKS the group delete, so the
# order there is not optional.
#
# Deploy order is Terraform's problem. The dependencies that matter and are not
# inferable from resource references alone are declared with depends_on:
#   * the scale set waits for the load balancer's outbound rule, because its
#     instances cannot reach the script-extension repository without a way out;
#   * the protected item waits for the NAT gateway association, because
#     enabling protection puts an agent on a machine that needs to call home.
#
# Roughly 10-15 minutes on the first run. The scale set's IIS install and the
# database server's gallery image dominate.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   AUTOTEARDOWN_DATE          YYYY-MM-DD for the AutoTeardown tag
#   AZURE_LOCATION             region for every resource (no fallback)
# Optional overrides, all prefixed so they cannot collide with another test
# bed's variables in the same env file:
#   VSI_WEB_VM_SIZE            web tier size; default Standard_D2s_v5
#   VSI_SQL_VM_SIZE            database server size; default Standard_D2s_v5
#   VSI_WEB_INSTANCE_COUNT     instances the scale set is created with
#   VSI_WEB_IMAGE_SKU          Windows Server image SKU (must be Gen2 for v5)
#   VSI_SQL_IMAGE_OFFER        gallery offer for the database server
#   VSI_SQL_IMAGE_SKU          gallery SKU for the database server
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- load env + pre-flight subscription guard --------------------------------
ENV_FILE="${HOME}/.azure/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_SUBSCRIPTION_ID, AUTOTEARDOWN_DATE, AZURE_LOCATION)" >&2
  exit 1
fi
: "${EXPECTED_SUBSCRIPTION_ID:?Set EXPECTED_SUBSCRIPTION_ID in ~/.azure/journeys.env}"
: "${AUTOTEARDOWN_DATE:?Set AUTOTEARDOWN_DATE=YYYY-MM-DD in ~/.azure/journeys.env}"
AZURE_LOCATION="${AZURE_LOCATION:?Set AZURE_LOCATION in ~/.azure/journeys.env}"
RESOURCE_GROUP="vsi-rg"

for tool in az terraform openssl; do
  command -v "$tool" >/dev/null || {
    echo "FATAL: $tool not found on PATH" >&2
    exit 1
  }
done

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [[ "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
  echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
  exit 1
fi
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
echo "Deploying azure/j5-vmss-sql-iaas to subscription $SUBSCRIPTION_ID, location $AZURE_LOCATION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

# ---- resource providers ------------------------------------------------------
# A subscription that has never created these resource types rejects the
# deployment with MissingSubscriptionRegistration. Registering is idempotent.
# microsoft.insights is the namespace autoscale settings live under, which is
# easy to miss because nothing else in this estate is a monitoring resource.
for ns in Microsoft.Compute Microsoft.Network Microsoft.Storage \
  Microsoft.OperationalInsights Microsoft.RecoveryServices Microsoft.Insights; do
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
  if [[ "$state" != "Registered" ]]; then
    echo ">>> Registering resource provider $ns (currently: $state)"
    az provider register --namespace "$ns" --wait
  fi
done

# ---- generated secret --------------------------------------------------------
# Azure wants >= 12 characters and three of four character classes, and rejects
# a password containing the login name. The random body is base64 alphanumerics
# and the Aa1_ suffix guarantees the classes. It travels to Terraform in the
# environment, so it never appears on a command line or in a file.
gen_password() {
  printf '%sAa1_' "$(openssl rand -base64 24 | tr -d '/+=')"
}
export TF_VAR_admin_password="$(gen_password)"

# ---- variables ---------------------------------------------------------------
export TF_VAR_location="$AZURE_LOCATION"
export TF_VAR_autoteardown_date="$AUTOTEARDOWN_DATE"

# Plain `[[ ... ]] && export` would abort under `set -e` whenever an override is
# unset, which is the normal case.
if [[ -n "${VSI_WEB_VM_SIZE:-}" ]]; then
  export TF_VAR_web_vm_size="$VSI_WEB_VM_SIZE"
  echo "Web tier size override: $VSI_WEB_VM_SIZE"
fi
if [[ -n "${VSI_SQL_VM_SIZE:-}" ]]; then
  export TF_VAR_sql_vm_size="$VSI_SQL_VM_SIZE"
  echo "Database server size override: $VSI_SQL_VM_SIZE"
fi
if [[ -n "${VSI_WEB_INSTANCE_COUNT:-}" ]]; then
  export TF_VAR_web_instance_count="$VSI_WEB_INSTANCE_COUNT"
  echo "Web tier instance count override: $VSI_WEB_INSTANCE_COUNT"
fi
if [[ -n "${VSI_WEB_IMAGE_SKU:-}" ]]; then
  export TF_VAR_web_image_sku="$VSI_WEB_IMAGE_SKU"
  echo "Web tier image override: $VSI_WEB_IMAGE_SKU"
fi
if [[ -n "${VSI_SQL_IMAGE_OFFER:-}" ]]; then
  export TF_VAR_sql_image_offer="$VSI_SQL_IMAGE_OFFER"
  echo "Database image offer override: $VSI_SQL_IMAGE_OFFER"
fi
if [[ -n "${VSI_SQL_IMAGE_SKU:-}" ]]; then
  export TF_VAR_sql_image_sku="$VSI_SQL_IMAGE_SKU"
  echo "Database image SKU override: $VSI_SQL_IMAGE_SKU"
fi

# ---- apply -------------------------------------------------------------------
echo ""
echo ">>> terraform apply (first run takes ~10-15 minutes)"
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -input=false -auto-approve

BASE_URL=$(terraform -chdir="$TF_DIR" output -raw base_url)
SCALE_SET=$(terraform -chdir="$TF_DIR" output -raw scale_set_name)
SQL_VM=$(terraform -chdir="$TF_DIR" output -raw sql_vm_name)
WORKSPACE=$(terraform -chdir="$TF_DIR" output -raw log_analytics_workspace_name)
VAULT=$(terraform -chdir="$TF_DIR" output -raw recovery_vault_name)

# ---- wait for the edge -------------------------------------------------------
# The probe cannot mark an instance healthy until the script extension has
# finished installing IIS, which lands a few minutes after the apply returns.
echo ""
echo ">>> Polling ${BASE_URL}/ until the edge answers..."
EDGE_UP=0
for _ in $(seq 1 36); do # up to 6 min
  if curl -sf -m 5 "${BASE_URL}/" >/dev/null 2>&1; then
    EDGE_UP=1
    break
  fi
  sleep 10
done

echo ""
echo "============================================================"
echo ">>> azure/j5-vmss-sql-iaas deployed to ${RESOURCE_GROUP}."
echo "BASE_URL=${BASE_URL}"
echo "SCALE_SET=${SCALE_SET}"
echo "SQL_VM=${SQL_VM}"
echo "LOG_ANALYTICS_WORKSPACE=${WORKSPACE}"
echo "RECOVERY_VAULT=${VAULT}"
echo ""
echo "The generated Windows administrator password was not printed and is not"
echo "stored. Re-run this script to rotate it."
echo ""
echo "There is no seed step: IIS and the status page are written by the scale"
echo "set's script extension at provisioning time."
if [[ "$EDGE_UP" != "1" ]]; then
  echo ""
  echo "WARNING: the edge did not answer within 6 min. A fresh load balancer and"
  echo "a first-boot IIS install can take a few extra minutes — retry shortly."
fi
echo ""
echo "Next step:"
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo "============================================================"
