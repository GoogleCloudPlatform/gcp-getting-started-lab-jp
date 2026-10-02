#!/usr/bin/env bash
# smoke-test.sh — acceptance test for azure/j8-clickops-partial-iac.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#   e.g. ./scripts/smoke-test.sh https://cpi-portal-abc123.azurewebsites.net
#        ./scripts/smoke-test.sh https://cpi-portal-xyz.a.run.app   (migrated GCP)
#
# CPI_EXPECTED_SQL_SKU and CPI_EXPECTED_APP_PLAN_SKU override the two SKUs this expects,
# for a subscription that had to be deployed onto different sizes than the
# template's defaults (see the deploy section of README.md).
#
# The HTTP checks are provider-agnostic: the same invocation is the acceptance
# test for a migrated GCP deployment of this workload. The Azure control-plane
# checks only run when the cpi-rg resource group is present in the current
# subscription, and are skipped — not failed — otherwise, so this script stays
# usable against a GCP target.
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

RESOURCE_GROUP="cpi-rg"
PASS=0
FAIL=0
SKIP=0

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
CPI_EXPECTED_SQL_SKU="${CPI_EXPECTED_SQL_SKU:-Basic}"
CPI_EXPECTED_APP_PLAN_SKU="${CPI_EXPECTED_APP_PLAN_SKU:-B1}"
if command -v az >/dev/null 2>&1 && SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null); then
  if [[ -n "${EXPECTED_SUBSCRIPTION_ID:-}" && "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
    echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
    exit 1
  fi
  if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
    AZURE_CONTEXT=1
  fi
fi

echo "Smoke-testing azure/j8-clickops-partial-iac at ${BASE_URL}"
echo ""

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
  fail "/health did not report status ok (body: ${HEALTH_BODY:0:200})"
fi

for dependency in notice_board document_library; do
  if grep -qE "\"${dependency}\": *\{[^}]*\"ok\": *true" <<<"$HEALTH_BODY"; then
    pass "/health dependency ${dependency} is ok"
  else
    fail "/health dependency ${dependency} is not ok"
  fi
done

# ---- 2. parity dashboard -----------------------------------------------------
CHECK_BODY=$(curl -sS --max-time 30 "${BASE_URL}/admin/azure-check" 2>/dev/null || echo "")
if grep -q '"all_ok": *true' <<<"$CHECK_BODY"; then
  pass "/admin/azure-check reports all_ok"
else
  fail "/admin/azure-check did not report all_ok (body: ${CHECK_BODY:0:300})"
fi

for service in sql_database blob_storage; do
  if grep -qE "\"${service}\": *\{[^}]*\"ok\": *true" <<<"$CHECK_BODY"; then
    pass "/admin/azure-check service ${service} is ok"
  else
    fail "/admin/azure-check service ${service} is not ok"
  fi
done

# ---- 3. the portal itself ----------------------------------------------------
BOARD_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "${BASE_URL}/" || echo "000")
if [[ "$BOARD_CODE" == "200" ]]; then
  pass "GET / returned 200"
else
  fail "GET / returned ${BOARD_CODE}, expected 200"
fi

BOARD_BODY=$(curl -sS --max-time 30 "${BASE_URL}/" 2>/dev/null || echo "")
if grep -q "The University" <<<"$BOARD_BODY"; then
  pass "notice board identifies The University"
else
  fail "notice board body did not contain 'The University'"
fi

# Notice 5 is the most recent, so it heads the board once the portal is seeded.
if grep -q "Summer opening hours for the Central Library" <<<"$BOARD_BODY"; then
  pass "notice board lists the seeded notices"
else
  fail "notice board did not list the seeded notices — has ./scripts/seed.sh run?"
fi

NOTICE_BODY=$(curl -sS --max-time 30 "${BASE_URL}/notices/4" 2>/dev/null || echo "")
if grep -q "First-semester examination timetable published" <<<"$NOTICE_BODY"; then
  pass "notice page for notice 4 renders"
else
  fail "notice page for notice 4 did not render"
fi

DOCUMENTS_BODY=$(curl -sS --max-time 30 "${BASE_URL}/documents" 2>/dev/null || echo "")
if grep -q "academic-calendar-2026.txt" <<<"$DOCUMENTS_BODY"; then
  pass "document library lists the published documents"
else
  fail "document library did not list the published documents"
fi

DOCUMENT_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
  "${BASE_URL}/documents/academic-calendar-2026.txt" || echo "000")
if [[ "$DOCUMENT_CODE" == "200" ]]; then
  pass "document served back from object storage"
else
  fail "document download returned ${DOCUMENT_CODE}, expected 200"
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
  else
    fail "no web app found in ${RESOURCE_GROUP}"
  fi

  PLAN_SKU=$(az appservice plan list --resource-group "$RESOURCE_GROUP" \
    --query "[0].sku.name" -o tsv 2>/dev/null || echo "")
  if [[ "$PLAN_SKU" == "$CPI_EXPECTED_APP_PLAN_SKU" ]]; then
    pass "App Service plan is ${CPI_EXPECTED_APP_PLAN_SKU}"
  else
    fail "App Service plan SKU was '${PLAN_SKU}', expected ${CPI_EXPECTED_APP_PLAN_SKU}"
  fi

  SQL_SERVER=$(az sql server list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$SQL_SERVER" ]]; then
    SQL_SKU=$(az sql db show --resource-group "$RESOURCE_GROUP" --server "$SQL_SERVER" \
      --name "cpiportal" --query "sku.name" -o tsv 2>/dev/null || echo "")
    if [[ "$SQL_SKU" == "$CPI_EXPECTED_SQL_SKU" ]]; then
      pass "database cpiportal is ${CPI_EXPECTED_SQL_SKU}"
    else
      fail "database cpiportal SKU was '${SQL_SKU}', expected ${CPI_EXPECTED_SQL_SKU}"
    fi
  else
    fail "no SQL logical server found in ${RESOURCE_GROUP}"
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
      --storage-account "$STORAGE" --name "documents" --output none 2>/dev/null; then
      pass "blob container 'documents' exists"
    else
      fail "blob container 'documents' not found on ${STORAGE}"
    fi
  else
    fail "no storage account found in ${RESOURCE_GROUP}"
  fi
else
  # One skip per check rather than one for the section, so the totals add up to
  # the same number of checks whichever provider this is pointed at.
  for check in "web app is Running" "App Service plan SKU" "database service objective" \
    "storage minimumTlsVersion" "blob container 'documents'"; do
    skip "${check} (no ${RESOURCE_GROUP} in the current subscription)"
  done
fi

# ---- summary -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo "PASS ${PASS}   FAIL ${FAIL}   SKIP ${SKIP}"
if [[ "$FAIL" -gt 0 ]]; then
  echo "smoke-test FAILED"
  exit 1
fi
echo "smoke-test OK"
