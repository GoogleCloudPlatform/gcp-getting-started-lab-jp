#!/usr/bin/env bash
# smoke-test.sh — acceptance test for azure/j7-container-apps-rag.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#   e.g. ./scripts/smoke-test.sh https://car-advisor.<env-suffix>.<region>.azurecontainerapps.io
#        ./scripts/smoke-test.sh https://car-advisor-abc123-an.a.run.app   (migrated GCP)
#
# CAR_EXPECTED_SEARCH_SKU overrides the search tier this expects, for a subscription
# that had to be deployed onto a different one (see the deploy section of
# README.md).
#
# The HTTP checks are provider-agnostic: the same invocation is the acceptance
# test for a migrated GCP deployment of this workload. The Azure control-plane
# checks only run when the car-rg resource group is present in the current
# subscription, and are skipped — not failed — otherwise, so this script stays
# usable against a GCP target.
#
# The explainer scales to zero, so the first request pays a cold start: an image
# pull and a Python start-up before anything answers. This polls /health/live
# until it does rather than assuming a warm replica. CAR_WARMUP_ATTEMPTS and
# CAR_WARMUP_INTERVAL (default 12 and 10s) set how long it is willing to wait.
#
# Where CAR_DEPLOY_ROLE_ASSIGNMENTS is set to anything but "true", the container
# app's identity has no grants on the model account, the search service or the
# documentation storage, so the index was never built and every explanation
# comes back uncited. The checks that depend on those report XFAIL: shown,
# counted, and not held against the run. Conversation history is unaffected —
# the Cosmos DB grant is a different switch — and the Azure control-plane checks
# still have to pass.
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

RESOURCE_GROUP="car-rg"
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
# A check that cannot pass while the container app's identity holds no grants on
# the model account, the search service or the documentation storage. Deploying
# without them is a supported posture, so in that posture these are reported and
# counted, but they do not make the run a failure.
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
# Resolved after the env file, so a lab-wide tier fallback can live there.
CAR_EXPECTED_SEARCH_SKU="${CAR_EXPECTED_SEARCH_SKU:-basic}"
if command -v az >/dev/null 2>&1 && SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null); then
  if [[ -n "${EXPECTED_SUBSCRIPTION_ID:-}" && "$SUBSCRIPTION_ID" != "$EXPECTED_SUBSCRIPTION_ID" ]]; then
    echo "FATAL: subscription mismatch (got $SUBSCRIPTION_ID, expected $EXPECTED_SUBSCRIPTION_ID)" >&2
    exit 1
  fi
  if az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
    AZURE_CONTEXT=1
  fi
fi

# Grants-off is a posture, not a fault: writing these role assignments needs
# more than Contributor on the scope, so a subscription administrator can apply
# them separately from the deployment. Read exactly the way the CLI reads the
# bool parameter it mirrors — anything that is not "true" turns the switch off.
GRANTS_OFF=0
if [[ -n "${CAR_DEPLOY_ROLE_ASSIGNMENTS:-}" && "${CAR_DEPLOY_ROLE_ASSIGNMENTS,,}" != "true" ]]; then
  GRANTS_OFF=1
fi

# ---- one request, one capture ------------------------------------------------
# Status, body and curl's own complaint all come out of the SAME request. Two
# curls for one check can disagree with each other, and a status printed from a
# different fetch than the body is worse than no status at all. HTTP_CODE is
# "000" whenever curl never got a reply — that is a transport failure (name did
# not resolve, nothing listening, handshake or budget expired), not a status the
# service chose, and http_detail prints the reason.
BODY_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$ERR_FILE"' EXIT

HTTP_CODE=""
HTTP_BODY=""
LAST_URL=""

http() {
  local method="$1" url="$2" budget="$3"
  shift 3
  LAST_URL="$url"
  : >"$ERR_FILE"
  if HTTP_CODE=$(curl -sS -o "$BODY_FILE" -w '%{http_code}' --max-time "$budget" \
    -X "$method" "$@" "$url" 2>"$ERR_FILE"); then
    :
  else
    HTTP_CODE="000"
  fi
  HTTP_BODY="$(cat "$BODY_FILE" 2>/dev/null || true)"
}

http_detail() {
  echo "      ${LAST_URL} -> ${HTTP_CODE}"
  if [[ -s "$ERR_FILE" ]]; then
    echo "      curl: $(tr '\n' ' ' <"$ERR_FILE" | cut -c1-200)"
  fi
  if [[ -n "$HTTP_BODY" ]]; then
    echo "      body: $(tr '\n' ' ' <<<"${HTTP_BODY}" | cut -c1-240)"
  fi
}

# ---- waking the explainer ------------------------------------------------------
# minReplicas is 0, so at the moment this script starts there is very often no
# replica at all. The first request has to wait for an image pull and a Python
# start-up, and a run that treats that wait as a failure tells you nothing about
# the estate. /health/live is the cheapest thing the app serves and the same
# path the platform's own start-up probe uses.
WARMUP_ATTEMPTS="${CAR_WARMUP_ATTEMPTS:-12}"
WARMUP_INTERVAL="${CAR_WARMUP_INTERVAL:-10}"

wake_up() {
  local attempt
  for ((attempt = 1; attempt <= WARMUP_ATTEMPTS; attempt++)); do
    http GET "${BASE_URL}/health/live" 30
    if [[ "$HTTP_CODE" == "200" ]]; then
      pass "the explainer answered (${attempt} attempt(s) to wake it)"
      return 0
    fi
    echo "      attempt ${attempt}/${WARMUP_ATTEMPTS}: ${HTTP_CODE} — waiting ${WARMUP_INTERVAL}s"
    sleep "$WARMUP_INTERVAL"
  done
  fail "the explainer never answered ${BASE_URL}/health/live"
  http_detail
  echo ""
  echo "      Nothing below this line can pass while that is true. A replica that"
  echo "      never answers is usually a replica that never started or one that is"
  echo "      being restarted underneath you:"
  echo "        az containerapp revision list -g ${RESOURCE_GROUP} -n <app> -o table"
  echo "        az containerapp logs show -g ${RESOURCE_GROUP} -n <app> --tail 100"
  echo "      Check the revision's running state and its replica restart count"
  echo "      before reading any of the failures that follow as real."
  echo ""
  return 1
}

echo "Smoke-testing azure/j7-container-apps-rag at ${BASE_URL}"
if [[ "$GRANTS_OFF" -eq 1 ]]; then
  echo "CAR_DEPLOY_ROLE_ASSIGNMENTS is not \"true\": the explainer's identity has no"
  echo "grants on the model account, the search service or the documentation"
  echo "storage, so the checks that need them are expected to fail, and are"
  echo "reported as XFAIL rather than counted against the run."
fi
echo ""

# ---- 0. wake the explainer -----------------------------------------------------
wake_up || true

# ---- 1. health ---------------------------------------------------------------
# One fetch. /health reaches three dependencies under a deadline apiece, so it
# is slower than /health/live by design and gets a budget to match: comfortably
# more than three deadlines, because a run where every dependency is dark is
# exactly the run whose body is worth reading, and curl gives back nothing at
# all if it gives up first.
http GET "${BASE_URL}/health" 100
HEALTH_BODY="$HTTP_BODY"
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "GET /health returned 200"
else
  fail "GET /health returned ${HTTP_CODE}, expected 200"
  http_detail
fi

if grep -q '"status": *"ok"' <<<"$HEALTH_BODY"; then
  pass "/health reports status ok"
else
  grant_dependent_fail "/health did not report status ok (body: ${HEALTH_BODY:0:250})"
fi

for dependency in search conversations documents; do
  if grep -qE "\"${dependency}\": *\{[^}]*\"ok\": *true" <<<"$HEALTH_BODY"; then
    pass "/health dependency ${dependency} is ok"
  elif [[ "$dependency" == "conversations" ]]; then
    # The conversation store is behind its own switch, so it is never excused.
    fail "/health dependency ${dependency} is not ok"
  else
    grant_dependent_fail "/health dependency ${dependency} is not ok"
  fi
done

# ---- 2. parity dashboard -----------------------------------------------------
# Six probes, one deadline each, so this is the slowest page the app serves, and
# the budget has to clear all six of them plus the wait for a reply.
http GET "${BASE_URL}/admin/azure-check" 150
CHECK_BODY="$HTTP_BODY"
[[ "$HTTP_CODE" == "200" ]] || http_detail
if grep -q '"all_ok": *true' <<<"$CHECK_BODY"; then
  pass "/admin/azure-check reports all_ok"
else
  grant_dependent_fail "/admin/azure-check did not report all_ok (body: ${CHECK_BODY:0:400})"
fi

for service in managed_identity openai search cosmos blob_storage telemetry; do
  if grep -qE "\"${service}\": *\{[^}]*\"ok\": *true" <<<"$CHECK_BODY"; then
    pass "/admin/azure-check service ${service} is ok"
  elif [[ "$service" == "openai" || "$service" == "search" || "$service" == "blob_storage" ]]; then
    grant_dependent_fail "/admin/azure-check service ${service} is not ok"
  else
    fail "/admin/azure-check service ${service} is not ok"
  fi
done

# ---- 3. the explainer itself -------------------------------------------------
SESSION_ID="smoke-$(date -u +%Y%m%d%H%M%S)"
http POST "${BASE_URL}/explain" 120 \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"${SESSION_ID}\",\"question\":\"Why does my portfolio hold a bond ladder?\"}"
EXPLAIN_BODY="$HTTP_BODY"
[[ "$HTTP_CODE" == "200" ]] || http_detail

if grep -q '"answer"' <<<"$EXPLAIN_BODY"; then
  pass "POST /explain returned an answer"
else
  fail "POST /explain returned no answer (body: ${EXPLAIN_BODY:0:300})"
fi

# Retrieval is what the citation list proves. It runs identically in stub and
# live mode, so this check is mode-independent — and it is the check that fails
# when the index was never built.
if grep -qE '"citations": *\[ *\{' <<<"$EXPLAIN_BODY"; then
  pass "POST /explain cited fund documentation"
else
  grant_dependent_fail "POST /explain returned no citations — has ./scripts/seed.sh run?"
fi

if grep -q 'CAR-BND' <<<"$EXPLAIN_BODY"; then
  pass "the bond ladder question retrieved the bond ladder fund"
else
  grant_dependent_fail "CAR-BND was not among the retrieved funds"
fi

if grep -q '"stored": *true' <<<"$EXPLAIN_BODY"; then
  pass "the explanation was written to the conversation store"
else
  fail "the explanation was not stored"
fi

# An empty question must be rejected, not answered.
http POST "${BASE_URL}/explain" 60 \
  -H 'Content-Type: application/json' -d '{"question":"  "}'
if [[ "$HTTP_CODE" == "400" ]]; then
  pass "POST /explain rejects an empty question with 400"
else
  fail "POST /explain returned ${HTTP_CODE} for an empty question, expected 400"
  http_detail
fi

# ---- 4. history round trip ---------------------------------------------------
http GET "${BASE_URL}/history/${SESSION_ID}" 60
HISTORY_BODY="$HTTP_BODY"
[[ "$HTTP_CODE" == "200" ]] || http_detail
if grep -q "\"session_id\": *\"${SESSION_ID}\"" <<<"$HISTORY_BODY"; then
  pass "GET /history returned the session just written"
else
  fail "GET /history did not return ${SESSION_ID} (body: ${HISTORY_BODY:0:300})"
fi

if grep -q 'bond ladder' <<<"$HISTORY_BODY"; then
  pass "the stored turn carries the question that was asked"
else
  fail "the stored turn did not carry the question"
fi

http GET "${BASE_URL}/history/sess-does-not-exist" 60
if [[ "$HTTP_CODE" == "404" ]]; then
  pass "GET /history returns 404 for an unknown session"
else
  fail "GET /history returned ${HTTP_CODE} for an unknown session, expected 404"
  http_detail
fi

# ---- 5. Azure control plane --------------------------------------------------
if [[ "$AZURE_CONTEXT" -eq 1 ]]; then
  APP=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$APP" ]]; then
    MIN_REPLICAS=$(az containerapp show --resource-group "$RESOURCE_GROUP" --name "$APP" \
      --query "properties.template.scale.minReplicas" -o tsv 2>/dev/null || echo "")
    if [[ "$MIN_REPLICAS" == "0" ]]; then
      pass "container app ${APP} scales to zero"
    else
      fail "container app ${APP} minReplicas was '${MIN_REPLICAS}', expected 0"
    fi

    REVISION_MODE=$(az containerapp show --resource-group "$RESOURCE_GROUP" --name "$APP" \
      --query "properties.configuration.activeRevisionsMode" -o tsv 2>/dev/null || echo "")
    if [[ "${REVISION_MODE,,}" == "single" ]]; then
      pass "container app ${APP} is in single-revision mode"
    else
      fail "container app ${APP} revision mode was '${REVISION_MODE}', expected Single"
    fi

    # Reported rather than asserted: the states this can legitimately hold with
    # minReplicas 0 depend on whether a replica happens to be up. Only the two
    # unambiguous ones are failures, and seeing this printed is what separates
    # "the app is broken" from "the app was never reachable".
    REV_STATE=$(az containerapp revision list --resource-group "$RESOURCE_GROUP" --name "$APP" \
      --query "[?properties.active]|[0].properties.runningState" -o tsv 2>/dev/null || echo "")
    echo "      active revision runningState: ${REV_STATE:-unknown}"
    case "${REV_STATE,,}" in
      failed | degraded)
        fail "the active revision of ${APP} is ${REV_STATE} — it cannot serve anything"
        ;;
      *) ;;
    esac
  else
    fail "no container app found in ${RESOURCE_GROUP}"
  fi

  ENV_NAME=$(az containerapp env list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$ENV_NAME" ]]; then
    SUBNET=$(az containerapp env show --resource-group "$RESOURCE_GROUP" --name "$ENV_NAME" \
      --query "properties.vnetConfiguration.infrastructureSubnetId" -o tsv 2>/dev/null || echo "")
    if [[ -n "$SUBNET" ]]; then
      pass "environment ${ENV_NAME} is integrated into a virtual network"
    else
      fail "environment ${ENV_NAME} has no infrastructure subnet — it cannot reach the private endpoints"
    fi
  else
    fail "no container apps environment found in ${RESOURCE_GROUP}"
  fi

  OPENAI=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$OPENAI" ]]; then
    PNA=$(az cognitiveservices account show --resource-group "$RESOURCE_GROUP" --name "$OPENAI" \
      --query "properties.publicNetworkAccess" -o tsv 2>/dev/null || echo "")
    if [[ "$PNA" == "Disabled" ]]; then
      pass "model account ${OPENAI} refuses public network access"
    else
      fail "model account ${OPENAI} publicNetworkAccess was '${PNA}', expected Disabled"
    fi
  else
    fail "no model account found in ${RESOURCE_GROUP}"
  fi

  SEARCH=$(az search service list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$SEARCH" ]]; then
    SEARCH_TIER=$(az search service show --resource-group "$RESOURCE_GROUP" --name "$SEARCH" \
      --query "sku.name" -o tsv 2>/dev/null || echo "")
    if [[ "${SEARCH_TIER,,}" == "${CAR_EXPECTED_SEARCH_SKU,,}" ]]; then
      pass "search service ${SEARCH} is ${CAR_EXPECTED_SEARCH_SKU}"
    else
      fail "search service ${SEARCH} tier was '${SEARCH_TIER}', expected ${CAR_EXPECTED_SEARCH_SKU}"
    fi
  else
    fail "no search service found in ${RESOURCE_GROUP}"
  fi

  PE_COUNT=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "$PE_COUNT" == "2" ]]; then
    pass "both private endpoints exist"
  else
    fail "found ${PE_COUNT} private endpoint(s) in ${RESOURCE_GROUP}, expected 2"
  fi

  ZONE_COUNT=$(az network private-dns zone list --resource-group "$RESOURCE_GROUP" \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ "$ZONE_COUNT" == "4" ]]; then
    pass "all four private DNS zones exist"
  else
    fail "found ${ZONE_COUNT} private DNS zone(s) in ${RESOURCE_GROUP}, expected 4"
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
  else
    fail "no storage account found in ${RESOURCE_GROUP}"
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
  echo "did not create. Apply Cognitive Services OpenAI User, Search Service"
  echo "Contributor, Search Index Data Contributor and Storage Blob Data Reader to"
  echo "the container app's identity, re-run ./scripts/seed.sh, then re-run this"
  echo "for a clean sheet."
  exit 0
fi
echo "smoke-test OK"
