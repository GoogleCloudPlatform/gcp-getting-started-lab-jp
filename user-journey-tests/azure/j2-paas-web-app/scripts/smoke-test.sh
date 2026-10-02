#!/usr/bin/env bash
# smoke-test.sh — acceptance test for azure/j2-paas-web-app.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#   e.g. ./scripts/smoke-test.sh https://pwa-shop-abc123.z01.azurefd.net
#        ./scripts/smoke-test.sh https://pwa-shop-xyz.a.run.app   (migrated GCP)
#
# PWA_EXPECTED_PG_SKU overrides the database SKU this expects, for a subscription
# that had to be deployed onto a different compute size than the template's
# default (see the deploy section of README.md).
#
# The HTTP checks are provider-agnostic: the same invocation is the acceptance
# test for a migrated GCP deployment of this workload. The Azure control-plane
# checks only run when the pwa-rg resource group is present in the current
# subscription, and are skipped — not failed — otherwise, so this script stays
# usable against a GCP target.
#
# The site is given a warm-up window before the first check, because a shop that
# was deployed a minute ago has not finished starting. PWA_WARMUP_ATTEMPTS (10) and
# PWA_WARMUP_INTERVAL (15 seconds) set how long that window is.
#
# Where PWA_DEPLOY_ROLE_ASSIGNMENTS is set to anything but "true", the web app's
# identity has no Key Vault or blob grants, and the checks that depend on them
# report XFAIL: shown, counted, and not held against the run. Everything else
# still has to pass.
#
# Exits nonzero if any check fails.
# -----------------------------------------------------------------------------

set -uo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "usage: $0 <BASE_URL>" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"

RESOURCE_GROUP="pwa-rg"
PASS=0
FAIL=0
SKIP=0
XFAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}
skip() {
  echo "SKIP  $1"
  SKIP=$((SKIP + 1))
}
# A check that cannot pass while the web app's identity holds no data-plane
# grants. Deploying without them is a supported posture, so in that posture
# these are reported and counted, but they do not make the run a failure.
grant_dependent_fail() {
  if [[ "$GRANTS_OFF" -eq 1 ]]; then
    echo "XFAIL $1"
    XFAIL=$((XFAIL + 1))
  else
    fail "$1"
  fi
}

# ---- load env + subscription guard -------------------------------------------
# The guard is advisory here rather than fatal: an HTTP-only run against a GCP
# frontend legitimately has no Azure context. It is fatal the moment we are
# pointed at a real subscription that is not the lab one.
AZURE_CONTEXT=0
ENV_FILE="${HOME}/.azure/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
# Resolved after the env file, so a lab-wide SKU fallback can live there.
PWA_EXPECTED_PG_SKU="${PWA_EXPECTED_PG_SKU:-Standard_B1ms}"
if command -v az >/dev/null 2>&1 && SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null); then
  if [[ -n "${EXPECTED_SUBSCRIPTION_ID:-}" && "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
    echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
    exit 1
  fi
  if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
    AZURE_CONTEXT=1
  fi
fi

# Grants-off is a posture, not a fault: the two data-plane role assignments can
# be applied by a subscription administrator separately from the deployment.
# Read exactly the way the CLI reads the bool parameter it mirrors — anything
# that is not "true" turns the switch off.
GRANTS_OFF=0
if [[ -n "${PWA_DEPLOY_ROLE_ASSIGNMENTS:-}" && "${PWA_DEPLOY_ROLE_ASSIGNMENTS,,}" != "true" ]]; then
  GRANTS_OFF=1
fi

echo "Smoke-testing azure/j2-paas-web-app at ${BASE_URL}"
if [[ "$GRANTS_OFF" -eq 1 ]]; then
  echo "PWA_DEPLOY_ROLE_ASSIGNMENTS is not \"true\": the checks that need the web"
  echo "app identity's Key Vault and blob grants are expected to fail, and are"
  echo "reported as XFAIL rather than counted against the run."
fi
echo ""

# ---- 0. warm-up ---------------------------------------------------------------
# A site that was deployed or restarted a moment ago is not a broken site. App
# Service builds the Python environment on the first request after a zip deploy,
# and Front Door needs a few probe intervals before it will route to a freshly
# healthy origin. Give the shop a bounded chance to answer before judging it.
PWA_WARMUP_ATTEMPTS="${PWA_WARMUP_ATTEMPTS:-10}"
PWA_WARMUP_INTERVAL="${PWA_WARMUP_INTERVAL:-15}"
WARMED=0
for attempt in $(seq 1 "$PWA_WARMUP_ATTEMPTS"); do
  WARMUP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "${BASE_URL}/health" 2>/dev/null || echo "000")
  if [[ "$WARMUP_CODE" == "200" || "$WARMUP_CODE" == "503" ]]; then
    # 503 here is the application's own answer, which means it is serving.
    WARMED=1
    [[ "$attempt" -gt 1 ]] && echo "      (answered on attempt ${attempt})"
    break
  fi
  if [[ "$attempt" -eq 1 ]]; then
    echo "      waiting for ${BASE_URL} to answer (up to $((PWA_WARMUP_ATTEMPTS * PWA_WARMUP_INTERVAL))s)"
  fi
  sleep "$PWA_WARMUP_INTERVAL"
done
if [[ "$WARMED" -eq 0 ]]; then
  echo "      no answer after $((PWA_WARMUP_ATTEMPTS * PWA_WARMUP_INTERVAL))s — running the checks anyway"
fi

# ---- 1. health ---------------------------------------------------------------
HEALTH_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "${BASE_URL}/health" || echo "000")
if [[ "$HEALTH_CODE" == "200" ]]; then
  pass "GET /health returned 200"
else
  fail "GET /health returned ${HEALTH_CODE}, expected 200"
fi

HEALTH_BODY=$(curl -sS --max-time 30 "${BASE_URL}/health" 2>/dev/null || echo "")
if grep -q '"status": *"ok"' <<<"$HEALTH_BODY"; then
  pass "/health reports status ok"
else
  grant_dependent_fail "/health did not report status ok (body: ${HEALTH_BODY:0:200})"
fi

for dependency in database blob vault; do
  if grep -qE "\"${dependency}\": *\{[^}]*\"ok\": *true" <<<"$HEALTH_BODY"; then
    pass "/health dependency ${dependency} is ok"
  elif [[ "$dependency" == "database" ]]; then
    fail "/health dependency ${dependency} is not ok"
  else
    grant_dependent_fail "/health dependency ${dependency} is not ok"
  fi
done

# ---- 2. parity dashboard -----------------------------------------------------
CHECK_BODY=$(curl -sS --max-time 30 "${BASE_URL}/admin/azure-check" 2>/dev/null || echo "")
if grep -q '"all_ok": *true' <<<"$CHECK_BODY"; then
  pass "/admin/azure-check reports all_ok"
else
  grant_dependent_fail "/admin/azure-check did not report all_ok (body: ${CHECK_BODY:0:300})"
fi

for service in managed_identity blob_storage key_vault postgresql telemetry; do
  if grep -qE "\"${service}\": *\{[^}]*\"ok\": *true" <<<"$CHECK_BODY"; then
    pass "/admin/azure-check service ${service} is ok"
  elif [[ "$service" == "blob_storage" || "$service" == "key_vault" ]]; then
    grant_dependent_fail "/admin/azure-check service ${service} is not ok"
  else
    fail "/admin/azure-check service ${service} is not ok"
  fi
done

# ---- 3. the shop itself ------------------------------------------------------
LIST_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "${BASE_URL}/" || echo "000")
if [[ "$LIST_CODE" == "200" ]]; then
  pass "GET / returned 200"
else
  fail "GET / returned ${LIST_CODE}, expected 200"
fi

LIST_BODY=$(curl -sS --max-time 30 "${BASE_URL}/" 2>/dev/null || echo "")
if grep -q "The Stationery Shop" <<<"$LIST_BODY"; then
  pass "catalogue page identifies The Stationery Shop"
else
  fail "catalogue page body did not contain 'The Stationery Shop'"
fi

if grep -q "6 items in the catalogue" <<<"$LIST_BODY"; then
  pass "catalogue page lists all six seeded products"
else
  fail "catalogue page did not report six products — has ./scripts/seed.sh run?"
fi

DETAIL_BODY=$(curl -sS --max-time 30 "${BASE_URL}/product/gold-leaf-notebook/" 2>/dev/null || echo "")
if grep -q "Gold-leaf cover notebook" <<<"$DETAIL_BODY"; then
  pass "product page for gold-leaf-notebook renders"
else
  fail "product page for gold-leaf-notebook did not render"
fi

# 3400 before tax, 3740 with the 10 percent consumption tax applied.
if grep -q "3740" <<<"$DETAIL_BODY"; then
  pass "product page shows the tax-inclusive price"
else
  fail "product page did not show the tax-inclusive price"
fi

IMAGE_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
  "${BASE_URL}/media/gold-leaf-notebook.svg" || echo "000")
if [[ "$IMAGE_CODE" == "200" ]]; then
  pass "product image served from object storage"
else
  grant_dependent_fail "product image returned ${IMAGE_CODE}, expected 200"
fi

# ---- 4. Azure control plane --------------------------------------------------
if [[ "$AZURE_CONTEXT" -eq 1 ]]; then
  WEB_APP=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$WEB_APP" ]]; then
    STATE=$(az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP" \
      --query "state" -o tsv 2>/dev/null || echo "")
    if [[ "$STATE" == "Running" ]]; then
      pass "web app ${WEB_APP} is Running"
    else
      fail "web app ${WEB_APP} state was '${STATE}', expected Running"
    fi

    SLOTS=$(az webapp deployment slot list --resource-group "$RESOURCE_GROUP" \
      --name "$WEB_APP" --query "[].name" -o tsv 2>/dev/null || echo "")
    if grep -qx "staging" <<<"$SLOTS"; then
      pass "staging deployment slot exists"
    else
      fail "staging deployment slot not found (slots: ${SLOTS:-none})"
    fi
  else
    fail "no web app found in ${RESOURCE_GROUP}"
  fi

  PG=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$PG" ]]; then
    PG_SKU=$(az postgres flexible-server show --resource-group "$RESOURCE_GROUP" \
      --name "$PG" --query "sku.name" -o tsv 2>/dev/null || echo "")
    if [[ "$PG_SKU" == "$PWA_EXPECTED_PG_SKU" ]]; then
      pass "flexible server ${PG} is ${PWA_EXPECTED_PG_SKU}"
    else
      fail "flexible server ${PG} SKU was '${PG_SKU}', expected ${PWA_EXPECTED_PG_SKU}"
    fi
  else
    fail "no PostgreSQL flexible server found in ${RESOURCE_GROUP}"
  fi

  STORAGE=$(az storage account list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$STORAGE" ]]; then
    TLS=$(az storage account show --resource-group "$RESOURCE_GROUP" --name "$STORAGE" \
      --query "minimumTlsVersion" -o tsv 2>/dev/null || echo "")
    if [[ "$TLS" == "TLS1_2" ]]; then
      pass "storage minimumTlsVersion is TLS1_2"
    else
      fail "storage minimumTlsVersion was '${TLS}', expected TLS1_2"
    fi

    if az storage container-rm show --resource-group "$RESOURCE_GROUP" \
      --storage-account "$STORAGE" --name "media" --output none 2>/dev/null; then
      pass "blob container 'media' exists"
    else
      fail "blob container 'media' not found on ${STORAGE}"
    fi
  else
    fail "no storage account found in ${RESOURCE_GROUP}"
  fi

  FD=$(az afd profile list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$FD" ]]; then
    pass "Front Door profile ${FD} exists"
  else
    fail "no Front Door profile found in ${RESOURCE_GROUP}"
  fi
else
  skip "Azure control-plane checks (no ${RESOURCE_GROUP} in the current subscription)"
fi

# ---- summary -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo "PASS ${PASS}   FAIL ${FAIL}   XFAIL ${XFAIL}   SKIP ${SKIP}"
if [[ "$FAIL" -gt 0 ]]; then
  echo "smoke-test FAILED"
  exit 1
fi
if [[ "$XFAIL" -gt 0 ]]; then
  echo "smoke-test OK — ${XFAIL} check(s) need the identity grants this deployment"
  echo "did not create. Apply Key Vault Secrets User and Storage Blob Data Reader"
  echo "to the web app's identity, then re-run for a clean sheet."
  exit 0
fi
echo "smoke-test OK"
