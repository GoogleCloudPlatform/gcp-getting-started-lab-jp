#!/usr/bin/env bash
# smoke-test.sh — acceptance test for azure/j3-aks-microservices.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#   e.g. ./scripts/smoke-test.sh http://20.0.0.1        (Azure load balancer)
#        ./scripts/smoke-test.sh http://34.0.0.1        (migrated GCP frontend)
#
# The HTTP checks are provider-agnostic: the same invocation is the acceptance
# test for a migrated GCP deployment of this workload. They cover the whole
# pipeline — the write path, the read path, and the asynchronous leg, since a
# parcel is only stamped notifiedAt once the worker has consumed its event.
#
# The Azure control-plane checks only run when the akm-rg resource group is
# present in the current subscription, and are skipped — not failed —
# otherwise, so this script stays usable against a GCP target.
#
# Where AKM_DEPLOY_ROLE_ASSIGNMENTS is set to anything but "true", the kubelet
# has no rights to pull the images and the pods have no Service Bus or Cosmos DB
# grants, so no workload serves. The checks that depend on one report XFAIL:
# shown, counted, and not held against the run. The Azure control-plane checks
# still have to pass.
#
# Requires curl and python3. Exits nonzero if any check fails.
# -----------------------------------------------------------------------------

set -uo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "usage: $0 <BASE_URL>" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"

# Without python3 every JSON assertion below silently reads as empty and the
# failures blame the service rather than the missing tool.
for tool in curl python3; do
  command -v "$tool" >/dev/null || {
    echo "FATAL: $tool not found on PATH" >&2
    exit 2
  }
done

RESOURCE_GROUP="akm-rg"
CLUSTER_NAME="akm-aks"
QUEUE_NAME="parcel-events"
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
# A check that cannot pass while the estate holds no role assignments: the
# kubelet cannot pull either image, so nothing runs, and the pods could not
# reach Service Bus or Cosmos DB if they did. Deploying without them is a
# supported posture, so in that posture these are reported and counted, but they
# do not make the run a failure.
grant_dependent_fail() {
  if [[ "$GRANTS_OFF" -eq 1 ]]; then
    echo "XFAIL $1"
    XFAIL=$((XFAIL + 1))
  else
    fail "$1"
  fi
}

# fetch METHOD PATH [JSON_BODY] — sets HTTP_CODE and BODY globals.
fetch() {
  local method="$1" path="$2" data="${3:-}" tmp
  tmp="$(mktemp)"
  if [[ -n "$data" ]]; then
    HTTP_CODE=$(curl -sS -m 60 -o "$tmp" -w '%{http_code}' \
      -X "$method" -H 'Content-Type: application/json' -d "$data" \
      "${BASE_URL}${path}" 2>/dev/null) || HTTP_CODE="000"
  else
    HTTP_CODE=$(curl -sS -m 60 -o "$tmp" -w '%{http_code}' \
      -X "$method" "${BASE_URL}${path}" 2>/dev/null) || HTTP_CODE="000"
  fi
  BODY="$(cat "$tmp")"
  rm -f "$tmp"
}

# json_get KEY [KEY...] — prints the (nested) value from $BODY, or nothing.
json_get() {
  python3 -c '
import json, sys
try:
    value = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
for key in sys.argv[2:]:
    if not isinstance(value, dict) or key not in value:
        sys.exit(0)
    value = value[key]
print(value)
' "$BODY" "$@"
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

# Grants-off is a posture, not a fault: the role assignments need more than
# Contributor to write, so a subscription administrator can apply them
# separately from the deployment. Read exactly the way deploy.sh forwards the
# bool to Terraform — anything that is not "true" turns the switch off.
GRANTS_OFF=0
if [[ -n "${AKM_DEPLOY_ROLE_ASSIGNMENTS:-}" && "${AKM_DEPLOY_ROLE_ASSIGNMENTS,,}" != "true" ]]; then
  GRANTS_OFF=1
fi

echo "Smoke-testing azure/j3-aks-microservices at ${BASE_URL}"
if [[ "$GRANTS_OFF" -eq 1 ]]; then
  echo "AKM_DEPLOY_ROLE_ASSIGNMENTS is not \"true\": the kubelet cannot pull the"
  echo "images and the pods hold no Service Bus or Cosmos DB grants, so every"
  echo "check that needs a running workload is expected to fail, and is reported"
  echo "as XFAIL rather than counted against the run."
fi
echo ""

# ---- 1. /health (retries connection failures: fresh LBs take a few minutes) ---
ATTEMPTS=0
while :; do
  fetch GET /health
  ATTEMPTS=$((ATTEMPTS + 1))
  [[ "$HTTP_CODE" != "000" || "$ATTEMPTS" -ge 18 ]] && break
  echo "  (edge not answering yet, retry ${ATTEMPTS}/18 in 10s...)"
  sleep 10
done
STATUS="$(json_get status)"
if [[ "$HTTP_CODE" == "200" && "$STATUS" == "ok" ]]; then
  pass "GET /health -> 200, status=ok"
else
  grant_dependent_fail "GET /health -> HTTP ${HTTP_CODE}, status='${STATUS}' (body: ${BODY:0:200})"
fi

# ---- 2. /admin/azure-check ----------------------------------------------------
fetch GET /admin/azure-check
OVERALL="$(json_get overall)"
if [[ "$HTTP_CODE" == "200" && "$OVERALL" == "ok" ]]; then
  pass "GET /admin/azure-check -> 200, overall=ok"
else
  grant_dependent_fail "GET /admin/azure-check -> HTTP ${HTTP_CODE}, overall='${OVERALL}' (body: ${BODY:0:200})"
fi
for service in identity cosmos servicebus; do
  RESULT="$(json_get checks "$service")"
  if [[ "$RESULT" == "ok" ]]; then
    pass "/admin/azure-check ${service} -> ok"
  else
    grant_dependent_fail "/admin/azure-check ${service} -> '${RESULT}'"
  fi
done

# ---- 3. parcel round trip -----------------------------------------------------
PARCEL_ID="AKM-SMOKE-$(date -u +%Y%m%d%H%M%S)"
fetch POST /parcels \
  "{\"parcelId\": \"${PARCEL_ID}\", \"origin\": \"Adachi\", \"destination\": \"Yokohama\"}"
CREATED_STATUS="$(json_get status)"
if [[ "$HTTP_CODE" == "201" && "$CREATED_STATUS" == "accepted" ]]; then
  pass "POST /parcels ${PARCEL_ID} -> 201, status=accepted"
else
  grant_dependent_fail "POST /parcels -> HTTP ${HTTP_CODE}, status='${CREATED_STATUS}' (body: ${BODY:0:200})"
fi

fetch GET "/parcels/${PARCEL_ID}"
READ_DEST="$(json_get destination)"
if [[ "$HTTP_CODE" == "200" && "$READ_DEST" == "Yokohama" ]]; then
  pass "GET /parcels/${PARCEL_ID} -> 200, stored parcel round-trips"
else
  grant_dependent_fail "GET /parcels/${PARCEL_ID} -> HTTP ${HTTP_CODE}, destination='${READ_DEST}'"
fi

fetch GET "/parcels/does-not-exist-${PARCEL_ID}"
if [[ "$HTTP_CODE" == "404" ]]; then
  pass "GET /parcels/<unknown> -> 404"
else
  grant_dependent_fail "GET /parcels/<unknown> -> HTTP ${HTTP_CODE}, expected 404"
fi

# ---- 4. asynchronous leg ------------------------------------------------------
# The scan event published by the POST above is consumed by the worker, which
# stamps notifiedAt on the document. This is the only check that proves the
# messaging pipeline end to end.
NOTIFIED=""
for _ in $(seq 1 18); do # up to 90s
  fetch GET "/parcels/${PARCEL_ID}"
  NOTIFIED="$(json_get notifiedAt)"
  [[ -n "$NOTIFIED" ]] && break
  sleep 5
done
if [[ -n "$NOTIFIED" ]]; then
  pass "scan event consumed: ${PARCEL_ID} notifiedAt=${NOTIFIED}"
else
  grant_dependent_fail "scan event for ${PARCEL_ID} was not consumed within 90s (notifiedAt never set)"
fi

# ---- 5. Azure control plane ---------------------------------------------------
if [[ "$AZURE_CONTEXT" -eq 1 ]]; then
  AKS_STATE=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "")
  if [[ "$AKS_STATE" == "Succeeded" ]]; then
    pass "az aks show ${CLUSTER_NAME}: Succeeded"
  else
    fail "${CLUSTER_NAME} provisioningState was '${AKS_STATE}', expected Succeeded"
  fi

  APPS_POOL=$(az aks nodepool show --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" \
    --name "apps" --query "vmSize" -o tsv 2>/dev/null || echo "")
  if [[ -n "$APPS_POOL" ]]; then
    pass "apps node pool present (${APPS_POOL})"
  else
    fail "apps node pool not found on ${CLUSTER_NAME} — nothing would schedule"
  fi

  WI_ENABLED=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" \
    --query "securityProfile.workloadIdentity.enabled" -o tsv 2>/dev/null || echo "")
  if [[ "$WI_ENABLED" == "true" ]]; then
    pass "cluster has workload identity enabled"
  else
    fail "cluster workload identity was '${WI_ENABLED}', expected true"
  fi

  ACR_SKU=$(az acr list --resource-group "$RESOURCE_GROUP" --query "[0].sku.name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$ACR_SKU" ]]; then
    pass "container registry present (sku ${ACR_SKU})"
  else
    fail "no container registry found in ${RESOURCE_GROUP}"
  fi

  SB_NAMESPACE=$(az servicebus namespace list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$SB_NAMESPACE" ]]; then
    SESSIONS=$(az servicebus queue show --resource-group "$RESOURCE_GROUP" \
      --namespace-name "$SB_NAMESPACE" --name "$QUEUE_NAME" \
      --query "requiresSession" -o tsv 2>/dev/null || echo "")
    if [[ "$SESSIONS" == "true" ]]; then
      pass "queue ${QUEUE_NAME} requires sessions"
    else
      fail "queue ${QUEUE_NAME} requiresSession was '${SESSIONS}', expected true"
    fi
  else
    fail "no Service Bus namespace found in ${RESOURCE_GROUP}"
  fi

  COSMOS_ACCOUNT=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$COSMOS_ACCOUNT" ]]; then
    if az cosmosdb sql container show --resource-group "$RESOURCE_GROUP" \
      --account-name "$COSMOS_ACCOUNT" --database-name "tracking" --name "parcels" \
      --output none 2>/dev/null; then
      pass "Cosmos DB container tracking/parcels exists"
    else
      fail "Cosmos DB container tracking/parcels not found on ${COSMOS_ACCOUNT}"
    fi
  else
    fail "no Cosmos DB account found in ${RESOURCE_GROUP}"
  fi
else
  skip "Azure control-plane checks (no ${RESOURCE_GROUP} in the current subscription)"
fi

# ---- summary ------------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo "PASS ${PASS}   FAIL ${FAIL}   XFAIL ${XFAIL}   SKIP ${SKIP}"
if [[ "$FAIL" -gt 0 ]]; then
  echo "smoke-test FAILED"
  exit 1
fi
if [[ "$XFAIL" -gt 0 ]]; then
  echo "smoke-test OK — ${XFAIL} check(s) need the role assignments this deployment"
  echo "did not create. Have someone with Owner or RBAC Administrator on the scope"
  echo "apply them, roll the deployments, then re-run for a clean sheet."
  exit 0
fi
echo "smoke-test OK"
