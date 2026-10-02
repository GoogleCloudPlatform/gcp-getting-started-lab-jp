#!/usr/bin/env bash
# smoke-test.sh — acceptance test for azure/j5-vmss-sql-iaas.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#   e.g. ./scripts/smoke-test.sh http://20.0.0.1        (Azure load balancer)
#        ./scripts/smoke-test.sh http://34.0.0.1        (migrated GCP frontend)
#
# The HTTP checks are provider-agnostic: the same invocation is the acceptance
# test for a migrated GCP deployment of this workload. They are all this estate
# has — there is no application API to exercise, because the MES web tier's
# entire published surface is the status page the scale set's script extension
# writes at provisioning time.
#
# The Azure control-plane checks only run when the vsi-rg resource group is
# present in the current subscription, and are skipped — not failed —
# otherwise, so this script stays usable against a GCP target.
#
# Requires curl. Exits nonzero if any check fails.
# -----------------------------------------------------------------------------

set -uo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "usage: $0 <BASE_URL>" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"

command -v curl >/dev/null || {
  echo "FATAL: curl not found on PATH" >&2
  exit 2
}

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

# fetch PATH — sets HTTP_CODE and BODY globals.
fetch() {
  local path="$1" tmp
  tmp="$(mktemp)"
  HTTP_CODE=$(curl -sS -m 30 -o "$tmp" -w '%{http_code}' "${BASE_URL}${path}" 2>/dev/null) || HTTP_CODE="000"
  BODY="$(cat "$tmp")"
  rm -f "$tmp"
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

# Set AFTER sourcing, never before: journeys.env is sourced by every test bed's
# scripts, and an unprefixed name defined in it would otherwise silently point
# these checks at somebody else's resource group.
RESOURCE_GROUP="vsi-rg"
SCALE_SET="vsi-mes-vmss"
SQL_VM="vsi-sql01"
WORKSPACE="vsi-law"

if command -v az >/dev/null 2>&1 && SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null); then
  if [[ -n "${EXPECTED_SUBSCRIPTION_ID:-}" && "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
    echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
    exit 1
  fi
  if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
    AZURE_CONTEXT=1
  fi
fi

echo "Smoke-testing azure/j5-vmss-sql-iaas at ${BASE_URL}"
echo ""

# ---- 1. the MES edge ----------------------------------------------------------
# Retries connection failures: a fresh load balancer plus a first-boot IIS
# install can take several minutes to start answering.
ATTEMPTS=0
while :; do
  fetch /
  ATTEMPTS=$((ATTEMPTS + 1))
  [[ "$HTTP_CODE" != "000" || "$ATTEMPTS" -ge 18 ]] && break
  echo "  (edge not answering yet, retry ${ATTEMPTS}/18 in 10s...)"
  sleep 10
done

if [[ "$HTTP_CODE" == "200" ]]; then
  pass "GET / -> 200"
else
  fail "GET / -> HTTP ${HTTP_CODE} (body: ${BODY:0:200})"
fi

if [[ "$BODY" == *"Precision-parts MES"* ]]; then
  pass "status page identifies the MES operator"
else
  fail "status page did not name the customer (body: ${BODY:0:200})"
fi

if [[ "$BODY" == *"status: ok"* ]]; then
  pass "status page reports status: ok"
else
  fail "status page did not report 'status: ok' (body: ${BODY:0:200})"
fi

# ---- 2. Azure control plane ---------------------------------------------------
if [[ "$AZURE_CONTEXT" -eq 1 ]]; then
  VMSS_STATE=$(az vmss show --resource-group "$RESOURCE_GROUP" --name "$SCALE_SET" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "")
  if [[ "$VMSS_STATE" == "Succeeded" ]]; then
    pass "az vmss show ${SCALE_SET}: Succeeded"
  else
    fail "${SCALE_SET} provisioningState was '${VMSS_STATE}', expected Succeeded"
  fi

  INSTANCE_COUNT=$(az vmss list-instances --resource-group "$RESOURCE_GROUP" --name "$SCALE_SET" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "$INSTANCE_COUNT" -ge 2 ]] 2>/dev/null; then
    pass "${SCALE_SET} is running ${INSTANCE_COUNT} instances"
  else
    fail "${SCALE_SET} reported ${INSTANCE_COUNT} instances, expected at least 2"
  fi

  SQL_POWER=$(az vm show --show-details --resource-group "$RESOURCE_GROUP" --name "$SQL_VM" \
    --query "powerState" -o tsv 2>/dev/null || echo "")
  if [[ "$SQL_POWER" == "VM running" ]]; then
    pass "${SQL_VM} powerState: VM running"
  else
    fail "${SQL_VM} powerState was '${SQL_POWER}', expected 'VM running'"
  fi

  # az resource show is used rather than the monitor command group so the check
  # does not depend on a CLI extension being installed.
  WORKSPACE_RETENTION=$(az resource show --resource-group "$RESOURCE_GROUP" --name "$WORKSPACE" \
    --resource-type "Microsoft.OperationalInsights/workspaces" \
    --query "properties.retentionInDays" -o tsv 2>/dev/null || echo "")
  if [[ -n "$WORKSPACE_RETENTION" ]]; then
    pass "log analytics workspace ${WORKSPACE} exists (retention ${WORKSPACE_RETENTION} days)"
  else
    fail "log analytics workspace ${WORKSPACE} not found in ${RESOURCE_GROUP}"
  fi

  VAULT=$(az backup vault list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$VAULT" ]]; then
    PROTECTED=$(az backup item list --resource-group "$RESOURCE_GROUP" --vault-name "$VAULT" \
      --backup-management-type AzureIaasVM \
      --query "[?properties.friendlyName=='${SQL_VM}'] | length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$PROTECTED" -ge 1 ]] 2>/dev/null; then
      pass "${SQL_VM} is a protected item in vault ${VAULT}"
    else
      fail "${SQL_VM} is not protected in vault ${VAULT}"
    fi
  else
    fail "no recovery services vault found in ${RESOURCE_GROUP}"
  fi
else
  skip "Azure control-plane checks (no ${RESOURCE_GROUP} in the current subscription)"
fi

# ---- summary ------------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo "PASS ${PASS}   FAIL ${FAIL}   SKIP ${SKIP}"
if [[ "$FAIL" -gt 0 ]]; then
  echo "smoke-test FAILED"
  exit 1
fi
echo "smoke-test OK"
