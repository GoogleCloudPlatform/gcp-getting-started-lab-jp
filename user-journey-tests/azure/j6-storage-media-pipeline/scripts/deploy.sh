#!/usr/bin/env bash
# deploy.sh — deploy the azure/j6-storage-media-pipeline test bed (the media-licensing operator, smp-*)
# to Azure.
# -----------------------------------------------------------------------------
# Requires terraform in addition to az: this estate is described in two
# dialects. The library — storage, the premium share, the sync service, the
# factory, the blob events — is the ARM template under arm/. The delivery edge
# — the public origin account and the Front Door profile in front of it — is
# the Terraform tree under terraform/.
#
# Idempotent: `az group create` is create-or-update, `terraform apply`
# converges, and `az deployment group create` runs in Incremental mode. There
# are no passwords anywhere in this estate, so a re-deploy rotates no
# credentials.
#
# Everything lands in ONE resource group (smp-rg) so teardown is a single
# `az group delete` after the retention policy has been cleared.
#
# DEPLOY ORDER
#   1. resource group             created here, carrying the tag block
#   2. terraform apply            delivery account, its public container, the
#                                 Front Door profile/endpoint/origin/route
#   3. az deployment group create the ARM template
#   4. seed                       one placeholder object in the public
#                                 container, so the edge has something to serve
#
# Both trees describe smpdelivery<suffix>. They are applied in the order above
# and ARM runs last, so where the two disagree about a property of that account
# the ARM value is the one left in place after a deploy. Terraform is not run
# again afterwards, so its state records what it applied rather than what is
# there; `terraform plan` reports the difference.
#
# The two trees agree on the account's NAME because SMP_NAME_SUFFIX below is
# derived once and handed to both.
#
# Required env vars (set them in ~/.azure/journeys.env):
#   EXPECTED_SUBSCRIPTION_ID   abort unless the current az context matches
#   AUTOTEARDOWN_DATE          YYYY-MM-DD for the AutoTeardown tag
#   AZURE_LOCATION             region for every resource (no fallback)
# Optional:
#   SMP_NAME_SUFFIX            override the derived 8-character suffix
#   SMP_FRONTDOOR_SKU          Front Door tier; default Standard_AzureFrontDoor
#   SMP_SKIP_EDGE_WAIT         "1" to skip polling the Front Door endpoint
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
RESOURCE_GROUP="smp-rg"

for tool in az terraform; do
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
echo "Deploying azure/j6-storage-media-pipeline to subscription $SUBSCRIPTION_ID, location $AZURE_LOCATION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARM_DIR="${SCRIPT_DIR}/../arm"
TF_DIR="${SCRIPT_DIR}/../terraform"

# ---- the shared name suffix --------------------------------------------------
# Three storage accounts and the data factory are global DNS names. The suffix
# is derived from the subscription and the group name, so it is stable for a
# given lab and different between labs — and, because it is computed once here,
# both trees name the delivery account identically.
if [[ -z "${SMP_NAME_SUFFIX:-}" ]]; then
  SMP_NAME_SUFFIX=$(printf '%s/%s' "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-8)
fi
if [[ ! "$SMP_NAME_SUFFIX" =~ ^[a-z0-9]{6,12}$ ]]; then
  echo "FATAL: SMP_NAME_SUFFIX must be 6-12 lowercase letters and digits (got '${SMP_NAME_SUFFIX}')" >&2
  exit 1
fi
DELIVERY_ACCOUNT="smpdelivery${SMP_NAME_SUFFIX}"
echo "Name suffix: ${SMP_NAME_SUFFIX}"

# ---- resource providers ------------------------------------------------------
# A subscription that has never created these resource types rejects the
# deployment with MissingSubscriptionRegistration. Registering is idempotent.
for ns in Microsoft.Storage Microsoft.StorageSync Microsoft.DataFactory \
  Microsoft.EventGrid Microsoft.Cdn; do
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
  if [[ "$state" != "Registered" ]]; then
    echo ">>> Registering resource provider $ns (currently: $state)"
    az provider register --namespace "$ns" --wait
  fi
done

# ---- region availability -----------------------------------------------------
# Not every provider offers every resource type in every region, and a
# deployment that finds out the hard way fails several minutes in with
# LocationNotAvailableForResourceType. Check the three least-universal types up
# front. `locations` comes back as display names ("West US 3"), so both sides
# are squashed to a comparable key.
LOCATION_KEY=$(printf '%s' "$AZURE_LOCATION" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
for pair in \
  "Microsoft.StorageSync:storageSyncServices" \
  "Microsoft.DataFactory:factories" \
  "Microsoft.EventGrid:systemTopics"; do
  ns="${pair%%:*}"
  rt="${pair##*:}"
  available=$(az provider show --namespace "$ns" \
    --query "resourceTypes[?resourceType=='${rt}'].locations[]" -o tsv 2>/dev/null \
    | tr -d ' ' | tr '[:upper:]' '[:lower:]' || echo "")
  if [[ -n "$available" ]] && ! grep -qx "$LOCATION_KEY" <<<"$available"; then
    echo "FATAL: ${ns}/${rt} is not offered in ${AZURE_LOCATION}." >&2
    echo "       Set AZURE_LOCATION in ~/.azure/journeys.env to one of:" >&2
    tr '\n' ' ' <<<"$available" | fold -s -w 100 | sed 's/^/         /' >&2
    exit 1
  fi
done

# ---- 1. resource group -------------------------------------------------------
echo ""
echo ">>> Creating resource group $RESOURCE_GROUP"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --tags \
  "Owner=migration-test" \
  "CostCenter=test-journeys" \
  "AutoTeardown=${AUTOTEARDOWN_DATE}" \
  "Journey=azure/j6-storage-media-pipeline" \
  --output none

# ---- 2. terraform apply (delivery edge) --------------------------------------
export TF_VAR_location="$AZURE_LOCATION"
export TF_VAR_autoteardown_date="$AUTOTEARDOWN_DATE"
export TF_VAR_name_suffix="$SMP_NAME_SUFFIX"
# Plain `[[ ... ]] && export` would abort the script under `set -e` whenever the
# override is unset, which is the normal case.
if [[ -n "${SMP_FRONTDOOR_SKU:-}" ]]; then
  export TF_VAR_frontdoor_sku="$SMP_FRONTDOOR_SKU"
  echo "Front Door tier override: $SMP_FRONTDOOR_SKU"
fi

echo ""
echo ">>> terraform apply (delivery edge)"
echo "    (Front Door provisioning dominates; allow ~5-10 minutes on a first run)"
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -auto-approve -input=false

BASE_URL=$(terraform -chdir="$TF_DIR" output -raw base_url)
DELIVERY_CONTAINER=$(terraform -chdir="$TF_DIR" output -raw delivery_container_name)
FD_PROFILE=$(terraform -chdir="$TF_DIR" output -raw frontdoor_profile_name)

# ---- 3. ARM deployment (the library) -----------------------------------------
DEPLOY_NAME="smp-deploy-$(date -u +%Y%m%d-%H%M%S)"
echo ""
echo ">>> Running deployment $DEPLOY_NAME (the library)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOY_NAME" \
  --template-file "${ARM_DIR}/azuredeploy.json" \
  --parameters "@${ARM_DIR}/azuredeploy.parameters.json" \
  --parameters autoTeardownDate="${AUTOTEARDOWN_DATE}" \
  --parameters nameSuffix="${SMP_NAME_SUFFIX}" \
  --output none

MEDIA_ACCOUNT=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
  --query properties.outputs.mediaAccountName.value -o tsv)
WIP_ACCOUNT=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
  --query properties.outputs.wipAccountName.value -o tsv)
DATA_FACTORY=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" --name "$DEPLOY_NAME" \
  --query properties.outputs.dataFactoryName.value -o tsv)

# ---- 4. seed the public container --------------------------------------------
# The origin needs one object for the edge to have anything to answer with, and
# the Front Door health probe is pointed at it. The account key is read at this
# moment and never written anywhere: --auth-mode login would need a Storage
# Blob Data role on top of Contributor, which this lab does not grant.
echo ""
echo ">>> Seeding the preview placeholder into ${DELIVERY_CONTAINER}/"
SEED_DIR="$(mktemp -d)"
trap 'rm -rf "$SEED_DIR"' EXIT
cat >"${SEED_DIR}/index.html" <<'HTML'
<!doctype html>
<html>
  <head><title>Media-licensing previews</title></head>
  <body>
    <h1>Media-licensing previews</h1>
    <p>Photo and video licensing library — preview delivery</p>
    <p>status: ok</p>
  </body>
</html>
HTML
printf 'ok\n' >"${SEED_DIR}/health.txt"

STORAGE_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" --account-name "$DELIVERY_ACCOUNT" \
  --query "[0].value" -o tsv)

for name in index.html health.txt; do
  case "$name" in
    *.html) content_type="text/html" ;;
    *) content_type="text/plain" ;;
  esac
  # --auth-mode is pinned rather than left to its default: journeys.env is
  # sourced above, and an AZURE_STORAGE_AUTH_MODE=login in it would switch this
  # to a data-plane role the lab's Contributor principal does not hold.
  az storage blob upload \
    --account-name "$DELIVERY_ACCOUNT" \
    --auth-mode key \
    --account-key "$STORAGE_KEY" \
    --container-name "$DELIVERY_CONTAINER" \
    --name "$name" \
    --file "${SEED_DIR}/${name}" \
    --content-type "$content_type" \
    --overwrite \
    --output none
done
unset STORAGE_KEY

# ---- 5. record the edge binding ----------------------------------------------
# A Front Door route serves a hostname only if it is linked to a domain: the
# route matches on protocol x domain x path, so a route linked to nothing
# matches nothing. That failure is invisible from outside — every request gets
# Front Door's own 404, which is byte for byte the page *.azurefd.net serves
# for a hostname that never existed — and it is invisible from the resource
# list too, because every resource still exists and still reports healthy.
# `az group delete` then destroys the only place the answer was written down.
# So read it here, while it can still be read, and print it in the banner.
ROUTE_LINKED="unknown"
FD_ENDPOINT=$(az afd endpoint list --resource-group "$RESOURCE_GROUP" \
  --profile-name "$FD_PROFILE" --query "[0].name" -o tsv 2>/dev/null || echo "")
FD_ROUTE=$(az afd route list --resource-group "$RESOURCE_GROUP" \
  --profile-name "$FD_PROFILE" --endpoint-name "$FD_ENDPOINT" \
  --query "[0].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$FD_ENDPOINT" && -n "$FD_ROUTE" ]]; then
  ROUTE_LINKED=$(az afd route show --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FD_PROFILE" --endpoint-name "$FD_ENDPOINT" \
    --route-name "$FD_ROUTE" --query linkToDefaultDomain -o tsv 2>/dev/null \
    || echo "unknown")
fi

# ---- 6. wait for the edge ----------------------------------------------------
# A new Front Door endpoint takes a few minutes to answer on its generated
# hostname. This is a convenience, not a gate: the deploy is done either way.
# EDGE_STATUS is echoed in the closing banner as well as here. The warning below
# goes to stderr, and a run captured by its tail can lose it — but whether the
# edge ever answered is the first thing anyone asks when the smoke test's HTTP
# checks fail, so it belongs in the banner on stdout too.
EDGE_STATUS="not polled (SMP_SKIP_EDGE_WAIT=1)"
if [[ "$ROUTE_LINKED" != "unknown" && "$ROUTE_LINKED" != "Enabled" ]]; then
  # Waiting does not fix a binding. Say so instead of burning ten minutes.
  EDGE_STATUS="not polled (route ${FD_ROUTE} linkToDefaultDomain=${ROUTE_LINKED})"
  echo ""
  echo ">>> Skipping the edge wait: route ${FD_ROUTE} is not linked to the default"
  echo "    domain, so ${BASE_URL} cannot answer however long we wait."
elif [[ "${SMP_SKIP_EDGE_WAIT:-0}" != "1" ]]; then
  echo ""
  echo ">>> Waiting for ${BASE_URL}/index.html to answer (up to 10 minutes)"
  edge_ready=0
  for attempt in $(seq 1 60); do
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "${BASE_URL}/index.html" 2>/dev/null || echo "000")
    if [[ "$code" == "200" ]]; then
      echo "    edge answered 200"
      EDGE_STATUS="answered 200 after ~$((attempt * 10))s"
      edge_ready=1
      break
    fi
    sleep 10
  done
  if [[ "$edge_ready" != "1" ]]; then
    EDGE_STATUS="no 200 within 10 minutes (last code: ${code})"
    echo "WARNING: the edge did not return 200 within 10 minutes (last code: ${code})." >&2
    echo "         Everything is deployed; re-run scripts/smoke-test.sh in a few minutes." >&2
  fi
fi

echo ""
echo "============================================================"
echo ">>> azure/j6-storage-media-pipeline deployed to $RESOURCE_GROUP."
echo "BASE_URL=${BASE_URL}"
echo "EDGE=${EDGE_STATUS}"
echo "ROUTE_LINKED_TO_DEFAULT_DOMAIN=${ROUTE_LINKED}"
echo "MEDIA_ACCOUNT=${MEDIA_ACCOUNT}"
echo "WIP_ACCOUNT=${WIP_ACCOUNT}"
echo "DELIVERY_ACCOUNT=${DELIVERY_ACCOUNT}"
echo "DATA_FACTORY=${DATA_FACTORY}"
echo ""
echo "No passwords or keys are stored by this script. The delivery account key"
echo "was read once to upload the placeholder and was not written anywhere."
echo ""
echo "The masters container carries a time-based retention policy, so"
echo "scripts/teardown.sh clears that policy before it deletes the group."
echo ""
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo "============================================================"
