#!/usr/bin/env bash
# smoke-test.sh — acceptance test for azure/j1-windows-iaas-lift.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#   e.g. ./scripts/smoke-test.sh http://20.0.0.1        (Azure load balancer)
#        ./scripts/smoke-test.sh http://34.0.0.1        (migrated GCP frontend)
#
# The HTTP checks are provider-agnostic: the same invocation is the
# acceptance test for a migrated GCP deployment of this workload. The Azure
# control-plane checks (SQL, storage) only run when the wil-rg resource group is
# present in the current subscription, and are skipped — not failed — otherwise,
# so this script stays usable against a GCP target.
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

RESOURCE_GROUP="wil-rg"
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
if command -v az >/dev/null 2>&1 && SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null); then
  if [[ -n "${EXPECTED_SUBSCRIPTION_ID:-}" && "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
    echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
    exit 1
  fi
  if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
    AZURE_CONTEXT=1
  fi
fi

echo "Smoke-testing azure/j1-windows-iaas-lift at ${BASE_URL}"
echo ""

# ---- 1. HTTP edge ------------------------------------------------------------
HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "${BASE_URL}/" || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "GET / returned 200"
else
  fail "GET / returned ${HTTP_CODE}, expected 200"
fi

BODY=$(curl -sS --max-time 20 "${BASE_URL}/" 2>/dev/null || echo "")
if grep -q "The clinic group (fictional)" <<<"$BODY"; then
  pass "status page identifies The clinic group (fictional)"
else
  fail "status page body did not contain 'The clinic group (fictional)'"
fi

if grep -q "status: ok" <<<"$BODY"; then
  pass "status page reports status: ok"
else
  fail "status page did not report 'status: ok'"
fi

# ---- 2. Azure control plane --------------------------------------------------
if [[ "$AZURE_CONTEXT" -eq 1 ]]; then
  SQL_SERVER=$(az sql server list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$SQL_SERVER" ]]; then
    DB_STATE=$(az sql db show --resource-group "$RESOURCE_GROUP" \
      --server "$SQL_SERVER" --name "wil-clinicdb" \
      --query "status" -o tsv 2>/dev/null || echo "")
    if [[ "$DB_STATE" == "Online" ]]; then
      pass "az sql db show wil-clinicdb on ${SQL_SERVER}: Online"
    else
      fail "wil-clinicdb status was '${DB_STATE}', expected Online"
    fi
  else
    fail "no Azure SQL logical server found in ${RESOURCE_GROUP}"
  fi

  STORAGE=$(az storage account list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$STORAGE" ]]; then
    pass "storage account ${STORAGE} exists"

    TLS=$(az storage account show --resource-group "$RESOURCE_GROUP" --name "$STORAGE" \
      --query "minimumTlsVersion" -o tsv 2>/dev/null || echo "")
    if [[ "$TLS" == "TLS1_2" ]]; then
      pass "storage minimumTlsVersion is TLS1_2"
    else
      fail "storage minimumTlsVersion was '${TLS}', expected TLS1_2"
    fi

    if az storage share-rm show --resource-group "$RESOURCE_GROUP" \
      --storage-account "$STORAGE" --name "scans" --output none 2>/dev/null; then
      pass "file share 'scans' exists"
    else
      fail "file share 'scans' not found on ${STORAGE}"
    fi

    if az storage container-rm show --resource-group "$RESOURCE_GROUP" \
      --storage-account "$STORAGE" --name "backups" --output none 2>/dev/null; then
      pass "blob container 'backups' exists"
    else
      fail "blob container 'backups' not found on ${STORAGE}"
    fi
  else
    fail "no storage account found in ${RESOURCE_GROUP}"
  fi
else
  skip "Azure control-plane checks (no ${RESOURCE_GROUP} in the current subscription)"
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
