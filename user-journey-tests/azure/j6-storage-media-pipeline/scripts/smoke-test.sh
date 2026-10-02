#!/usr/bin/env bash
# smoke-test.sh — acceptance test for azure/j6-storage-media-pipeline.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh <BASE_URL>
#   e.g. ./scripts/smoke-test.sh https://smp-media-edge-abc123.z01.azurefd.net
#        ./scripts/smoke-test.sh https://34.0.0.1        (migrated GCP edge)
#
# The HTTP checks are provider-agnostic: the same invocation is the acceptance
# test for a migrated GCP deployment of this workload, where the edge is a load
# balancer in front of a bucket rather than Front Door in front of a container.
# The Azure control-plane checks only run when the smp-rg resource group is
# present in the current subscription, and are skipped — not failed —
# otherwise, so this script stays usable against a GCP target.
#
# The control-plane checks run FIRST, on purpose. An edge that is misconfigured
# and an edge that is merely young look identical from outside — both answer
# 404 — but only one of them is worth waiting for. Reading the configuration
# before spending the warm-up window turns a ten-minute mystery into an
# immediate answer, and the warm-up is skipped outright when the configuration
# already proves the edge cannot serve.
#
# The edge is then given a warm-up window, because an edge deployed a few
# minutes ago has not finished becoming an edge. SMP_WARMUP_ATTEMPTS (20) and
# SMP_WARMUP_INTERVAL (30 seconds) set how long that window is; the default is
# ten minutes.
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

RESOURCE_GROUP="smp-rg"
PASS=0
FAIL=0
SKIP=0

# Set when a control-plane check proves the edge cannot serve this hostname at
# all, which makes the HTTP warm-up window pointless.
EDGE_BINDING_BAD=0

# Set when the bindings are correct but the edge push (deploymentStatus) has not
# reached the POPs yet. Advisory only — this is Azure's edge-propagation stage,
# not a misconfiguration, and Front Door can read NotStarted while it is already
# serving, so it never gates. The HTTP checks below are the arbiter.
EDGE_ROLLOUT_PENDING=0

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
# Advisory line: neither pass nor fail, kept out of the counts on purpose.
note() {
  echo "NOTE  $1"
}

# ---- load env + subscription guard -------------------------------------------
# The guard is advisory here rather than fatal: an HTTP-only run against a GCP
# edge legitimately has no Azure context. It is fatal the moment we are pointed
# at a real subscription that is not the lab one.
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

echo "Smoke-testing azure/j6-storage-media-pipeline at ${BASE_URL}"
echo ""

INDEX_URL="${BASE_URL}/index.html"
HEALTH_URL="${BASE_URL}/health.txt"

# One request, both halves of the answer. The body assertions used to re-issue
# the request they were judged against, so the status line and the body could
# come from two different responses — and every failure line has to name the
# URL and the status it got, because a run captured by its tail loses the
# checks that ran first, which are exactly these.
HTTP_CODE=""
HTTP_BODY=""
http_get() {
  local raw
  raw=$(curl -sS -w '\n%{http_code}' --max-time 25 "$1" 2>/dev/null) || raw=$'\n000'
  HTTP_CODE="${raw##*$'\n'}"
  HTTP_BODY="${raw%$'\n'*}"
}

# The first 120 characters of the body, on one line. Enough to tell Front Door's
# own 404 — an edge still propagating, or no route matched — apart from the
# origin's, which is XML carrying <Code>BlobNotFound</Code> or
# <Code>ContainerNotFound</Code>. Those two have entirely different fixes.
#
# Front Door's own 404 is a ~266 KB HTML page titled "Page not found", sent
# with `x-cache: CONFIG_NOCACHE`. Do not read it as evidence about this
# profile: it is byte for byte the page *.azurefd.net returns for a hostname
# that has never existed, because that namespace is wildcard DNS onto the Front
# Door anycast. It means "no configuration is serving this hostname here" and
# nothing more precise — which is why the control-plane checks above exist.
body_excerpt() {
  tr '\n' ' ' <<<"$1" | cut -c1-120
}

# ---- 1. Azure control plane --------------------------------------------------
if [[ "$AZURE_CONTEXT" -eq 1 ]]; then
  MEDIA=$(az storage account list --resource-group "$RESOURCE_GROUP" \
    --query "[?starts_with(name, 'smpmedia')] | [0].name" -o tsv 2>/dev/null || echo "")
  WIP=$(az storage account list --resource-group "$RESOURCE_GROUP" \
    --query "[?starts_with(name, 'smpwip')] | [0].name" -o tsv 2>/dev/null || echo "")
  DELIVERY=$(az storage account list --resource-group "$RESOURCE_GROUP" \
    --query "[?starts_with(name, 'smpdelivery')] | [0].name" -o tsv 2>/dev/null || echo "")

  if [[ -n "$MEDIA" ]]; then
    pass "library storage account ${MEDIA} exists"

    SKU=$(az storage account show --resource-group "$RESOURCE_GROUP" --name "$MEDIA" \
      --query "sku.name" -o tsv 2>/dev/null || echo "")
    if [[ "$SKU" == "Standard_RAGRS" ]]; then
      pass "library redundancy is Standard_RAGRS"
    else
      fail "library redundancy was '${SKU}', expected Standard_RAGRS"
    fi

    TLS=$(az storage account show --resource-group "$RESOURCE_GROUP" --name "$MEDIA" \
      --query "minimumTlsVersion" -o tsv 2>/dev/null || echo "")
    if [[ "$TLS" == "TLS1_2" ]]; then
      pass "library minimumTlsVersion is TLS1_2"
    else
      fail "library minimumTlsVersion was '${TLS}', expected TLS1_2"
    fi

    for container in masters proxies intake; do
      if az storage container-rm show --resource-group "$RESOURCE_GROUP" \
        --storage-account "$MEDIA" --name "$container" --output none 2>/dev/null; then
        pass "blob container '${container}' exists"
      else
        fail "blob container '${container}' not found on ${MEDIA}"
      fi
    done

    RULES=$(az storage account management-policy show \
      --resource-group "$RESOURCE_GROUP" --account-name "$MEDIA" \
      --query "length(policy.rules)" -o tsv 2>/dev/null || echo "")
    if [[ "$RULES" == "3" ]]; then
      pass "lifecycle management policy carries 3 rules"
    else
      fail "lifecycle management policy reported '${RULES}' rules, expected 3"
    fi

    # The CLI flattens the policy's properties, but query both shapes rather
    # than depend on that: an empty answer here would read as "no policy".
    IMMUTABLE=$(az storage container immutability-policy show \
      --resource-group "$RESOURCE_GROUP" --account-name "$MEDIA" \
      --container-name "masters" --query "[state, properties.state] | [?@] | [0]" \
      -o tsv 2>/dev/null || echo "")
    if [[ "$IMMUTABLE" == "Unlocked" ]]; then
      pass "masters retention policy is present and Unlocked"
    else
      fail "masters retention policy state was '${IMMUTABLE}', expected Unlocked"
    fi
  else
    fail "no smpmedia* storage account found in ${RESOURCE_GROUP}"
  fi

  if [[ -n "$WIP" ]]; then
    if az storage share-rm show --resource-group "$RESOURCE_GROUP" \
      --storage-account "$WIP" --name "wip-edit" --output none 2>/dev/null; then
      pass "premium file share 'wip-edit' exists"
    else
      fail "file share 'wip-edit' not found on ${WIP}"
    fi
  else
    fail "no smpwip* storage account found in ${RESOURCE_GROUP}"
  fi

  if [[ -n "$DELIVERY" ]]; then
    pass "delivery storage account ${DELIVERY} exists"
  else
    fail "no smpdelivery* storage account found in ${RESOURCE_GROUP}"
  fi

  SYNC=$(az resource list --resource-group "$RESOURCE_GROUP" \
    --resource-type "Microsoft.StorageSync/storageSyncServices" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$SYNC" ]]; then
    pass "storage sync service ${SYNC} exists"
  else
    fail "no Microsoft.StorageSync/storageSyncServices found in ${RESOURCE_GROUP}"
  fi

  TOPIC=$(az eventgrid system-topic list --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$TOPIC" ]]; then
    SUBS=$(az eventgrid system-topic event-subscription list \
      --resource-group "$RESOURCE_GROUP" --system-topic-name "$TOPIC" \
      --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$SUBS" -ge 1 ]]; then
      pass "event grid system topic ${TOPIC} has ${SUBS} subscription(s)"
    else
      fail "event grid system topic ${TOPIC} has no subscriptions"
    fi
  else
    fail "no Event Grid system topic found in ${RESOURCE_GROUP}"
  fi

  FACTORY=$(az resource list --resource-group "$RESOURCE_GROUP" \
    --resource-type "Microsoft.DataFactory/factories" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$FACTORY" ]]; then
    pass "data factory ${FACTORY} exists"
  else
    fail "no Microsoft.DataFactory/factories found in ${RESOURCE_GROUP}"
  fi

  PROFILE=$(az resource list --resource-group "$RESOURCE_GROUP" \
    --resource-type "Microsoft.Cdn/profiles" \
    --query "[0].name" -o tsv 2>/dev/null || echo "")
  if [[ -n "$PROFILE" ]]; then
    pass "edge profile ${PROFILE} exists"

    # ---- the edge binding ----
    # Everything above proves the profile exists. None of it proves the profile
    # SERVES anything, and those are different questions: a Front Door route
    # matches on protocol x domain x path, so a route linked to no domain
    # matches nothing at all. Every resource still reports healthy, every
    # existence check still passes, and every request to the endpoint gets
    # Front Door's own 404 — a signature that cannot be recognised from the
    # client side, because it is identical to a hostname that was never
    # created. So read the binding from the control plane rather than
    # inferring it from a status code.
    ENDPOINT=$(az afd endpoint list --resource-group "$RESOURCE_GROUP" \
      --profile-name "$PROFILE" --query "[0].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$ENDPOINT" ]]; then
      # One query per field on purpose: `az ... --query "[a, b, c]" -o tsv`
      # renders a JSON array as NEWLINE-separated values, one per line, not
      # tab-separated. A single `read` with IFS=tab then captures only the
      # first field and leaves the rest empty, which reads as a broken binding
      # when the binding is fine. Separate scalar queries sidestep the shape.
      EP_STATE=$(az afd endpoint show --resource-group "$RESOURCE_GROUP" \
        --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
        --query enabledState -o tsv 2>/dev/null || echo "")
      EP_HOST=$(az afd endpoint show --resource-group "$RESOURCE_GROUP" \
        --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
        --query hostName -o tsv 2>/dev/null || echo "")
      EP_DS=$(az afd endpoint show --resource-group "$RESOURCE_GROUP" \
        --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
        --query deploymentStatus -o tsv 2>/dev/null || echo "")

      if [[ "$EP_STATE" == "Enabled" ]]; then
        pass "edge endpoint ${ENDPOINT} is Enabled"
      else
        fail "edge endpoint ${ENDPOINT} enabledState was '${EP_STATE}', expected Enabled"
        EDGE_BINDING_BAD=1
      fi

      if [[ "https://${EP_HOST}" == "$BASE_URL" ]]; then
        pass "edge endpoint hostname is the one under test (${EP_HOST})"
      else
        fail "edge endpoint hostname is '${EP_HOST}', but this run is testing ${BASE_URL}"
        EDGE_BINDING_BAD=1
      fi

      ROUTE=$(az afd route list --resource-group "$RESOURCE_GROUP" \
        --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
        --query "[0].name" -o tsv 2>/dev/null || echo "")
      if [[ -n "$ROUTE" ]]; then
        # Separate scalar queries, for the newline-vs-tab reason above. The
        # patterns are an array, so they are joined to a scalar in the query.
        R_STATE=$(az afd route show --resource-group "$RESOURCE_GROUP" \
          --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
          --route-name "$ROUTE" --query enabledState -o tsv 2>/dev/null || echo "")
        R_LINK=$(az afd route show --resource-group "$RESOURCE_GROUP" \
          --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
          --route-name "$ROUTE" --query linkToDefaultDomain -o tsv 2>/dev/null || echo "")
        R_ORIGINPATH=$(az afd route show --resource-group "$RESOURCE_GROUP" \
          --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
          --route-name "$ROUTE" --query originPath -o tsv 2>/dev/null || echo "")
        R_PATTERNS=$(az afd route show --resource-group "$RESOURCE_GROUP" \
          --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
          --route-name "$ROUTE" --query "join(',', patternsToMatch)" -o tsv 2>/dev/null || echo "")
        R_DS=$(az afd route show --resource-group "$RESOURCE_GROUP" \
          --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
          --route-name "$ROUTE" --query deploymentStatus -o tsv 2>/dev/null || echo "")

        if [[ "$R_STATE" == "Enabled" ]]; then
          pass "route ${ROUTE} is Enabled"
        else
          fail "route ${ROUTE} enabledState was '${R_STATE}', expected Enabled"
          EDGE_BINDING_BAD=1
        fi

        # There is no custom domain on this estate, so the default domain is
        # the only domain the route can be linked to. Unlinked, it serves
        # nothing on the *.azurefd.net hostname.
        if [[ "$R_LINK" == "Enabled" ]]; then
          pass "route ${ROUTE} is linked to the default domain"
        else
          fail "route ${ROUTE} linkToDefaultDomain was '${R_LINK}', expected Enabled — an unlinked route matches no request, so every path under ${BASE_URL} returns Front Door's own 404 no matter how long you wait"
          EDGE_BINDING_BAD=1
        fi

        if [[ "$R_PATTERNS" == *"/*"* ]]; then
          pass "route ${ROUTE} matches /* (patterns: ${R_PATTERNS})"
        else
          fail "route ${ROUTE} patternsToMatch was '${R_PATTERNS}', expected to include /*"
          EDGE_BINDING_BAD=1
        fi

        if [[ "$R_ORIGINPATH" == "/public/" ]]; then
          pass "route ${ROUTE} prepends the delivery container (originPath /public/)"
        else
          fail "route ${ROUTE} originPath was '${R_ORIGINPATH}', expected '/public/' — the trailing slash is load-bearing, '/public' forwards /index.html to /publicindex.html"
        fi

        # deploymentStatus is a third question, distinct from enabledState and
        # provisioningState: whether Front Door has pushed this accepted config
        # out to the edge POPs. A route can be Enabled and Succeeded yet still
        # read NotStarted here, and every request then gets the anycast 404
        # until the push lands — Microsoft documents up to ~45 minutes, and a
        # fresh profile occasionally needs a re-apply nudge to start it. This is
        # advisory, never a failure: Front Door can read NotStarted while it is
        # already serving, so the HTTP checks below stay the arbiter.
        if [[ "$EP_DS" == "Succeeded" && "$R_DS" == "Succeeded" ]]; then
          note "edge rollout deploymentStatus Succeeded (endpoint and route are pushed to the POPs)"
        else
          note "edge rollout deploymentStatus: endpoint='${EP_DS}' route='${R_DS}' — config is accepted but not yet confirmed on the POPs, so a 404 below is the edge-push stage rather than a binding fault (Microsoft: up to ~45 min; a fresh profile may need a re-apply nudge)"
          EDGE_ROLLOUT_PENDING=1
        fi
      else
        fail "no route found on Front Door endpoint ${ENDPOINT} — an endpoint with no route serves nothing"
        EDGE_BINDING_BAD=1
      fi
    else
      fail "no Front Door endpoint found in profile ${PROFILE}"
      EDGE_BINDING_BAD=1
    fi

    OG=$(az afd origin-group list --resource-group "$RESOURCE_GROUP" \
      --profile-name "$PROFILE" --query "[0].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$OG" ]]; then
      # Separate scalar queries, for the newline-vs-tab reason above.
      O_HOST=$(az afd origin list --resource-group "$RESOURCE_GROUP" \
        --profile-name "$PROFILE" --origin-group-name "$OG" \
        --query "[0].hostName" -o tsv 2>/dev/null || echo "")
      O_HEADER=$(az afd origin list --resource-group "$RESOURCE_GROUP" \
        --profile-name "$PROFILE" --origin-group-name "$OG" \
        --query "[0].originHostHeader" -o tsv 2>/dev/null || echo "")

      if [[ -n "$O_HOST" ]]; then
        pass "origin group ${OG} has an origin (${O_HOST})"
      else
        fail "origin group ${OG} has no origins"
      fi

      # Storage answers a request only when the Host header names the storage
      # account. Front Door forwards the endpoint hostname unless this is set,
      # and storage then refuses a blob it is perfectly willing to serve.
      if [[ -n "$O_HEADER" && "$O_HEADER" == "$O_HOST" ]]; then
        pass "origin host header matches the origin hostname"
      else
        fail "origin hostName is '${O_HOST}' but originHostHeader is '${O_HEADER}' — storage serves a request only when the Host header names the storage account"
      fi
    else
      fail "no origin group found in profile ${PROFILE}"
    fi
  else
    fail "no Microsoft.Cdn/profiles found in ${RESOURCE_GROUP}"
  fi
else
  skip "Azure control-plane checks (no ${RESOURCE_GROUP} in the current subscription)"
fi

echo ""

# ---- 2. warm-up --------------------------------------------------------------
# An edge deployed a few minutes ago is not a broken edge. Two clocks have to
# run out before it can answer: the profile's configuration has to reach the
# POPs, and the origin has to pass enough health probes to be called healthy —
# at the 100-second probe interval terraform/frontdoor.tf configures, needing 3
# good samples out of 4, that second clock alone is ~5 minutes from the moment
# the blobs land. scripts/deploy.sh already waits up to 10 minutes after
# seeding; this is the same courtesy for a smoke run started by hand, and it is
# why a fresh deploy should be given both windows rather than either one.
SMP_WARMUP_ATTEMPTS="${SMP_WARMUP_ATTEMPTS:-20}"
SMP_WARMUP_INTERVAL="${SMP_WARMUP_INTERVAL:-30}"
WARMED=0
if [[ "$EDGE_BINDING_BAD" -eq 1 ]]; then
  echo "      skipping the warm-up: the control-plane checks above already show the edge"
  echo "      cannot serve ${BASE_URL}, and waiting does not fix a binding"
else
  for attempt in $(seq 1 "$SMP_WARMUP_ATTEMPTS"); do
    http_get "$INDEX_URL"
    if [[ "$HTTP_CODE" == "200" ]]; then
      WARMED=1
      [[ "$attempt" -gt 1 ]] && echo "      (edge answered on attempt ${attempt})"
      break
    fi
    if [[ "$attempt" -eq 1 ]]; then
      echo "      waiting for ${INDEX_URL} to answer 200 (up to $((SMP_WARMUP_ATTEMPTS * SMP_WARMUP_INTERVAL))s; first try: HTTP ${HTTP_CODE})"
    fi
    [[ "$attempt" -lt "$SMP_WARMUP_ATTEMPTS" ]] && sleep "$SMP_WARMUP_INTERVAL"
  done
  if [[ "$WARMED" -eq 0 ]]; then
    echo "      no 200 after $((SMP_WARMUP_ATTEMPTS * SMP_WARMUP_INTERVAL))s (last: HTTP ${HTTP_CODE}) — running the checks anyway"
  fi
fi

# ---- 3. the delivery edge ----------------------------------------------------
# The edge serves objects from a container prefix, so there is no document at
# the root; index.html is the landing object the deploy seeds.
http_get "$INDEX_URL"
INDEX_CODE="$HTTP_CODE"
INDEX_BODY="$HTTP_BODY"

if [[ "$INDEX_CODE" == "200" ]]; then
  pass "GET ${INDEX_URL} returned 200"
else
  fail "GET ${INDEX_URL} returned ${INDEX_CODE}, expected 200 — body: $(body_excerpt "$INDEX_BODY")"
  [[ "$EDGE_ROLLOUT_PENDING" -eq 1 ]] &&
    echo "      deploymentStatus was not Succeeded when the bindings were read (see the NOTE above): this is the edge push not having reached the POPs, not a misconfiguration — re-run in a few minutes or nudge with 'az afd route update'"
fi

if grep -q "Media-licensing previews" <<<"$INDEX_BODY"; then
  pass "delivery page identifies the media-licensing operator"
else
  fail "delivery page body did not contain 'Media-licensing previews' (${INDEX_URL}, HTTP ${INDEX_CODE}) — body: $(body_excerpt "$INDEX_BODY")"
fi

if grep -q "status: ok" <<<"$INDEX_BODY"; then
  pass "delivery page reports status: ok"
else
  fail "delivery page did not report 'status: ok' (${INDEX_URL}, HTTP ${INDEX_CODE})"
fi

http_get "$HEALTH_URL"
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "GET ${HEALTH_URL} returned 200 (the edge health probe target)"
else
  fail "GET ${HEALTH_URL} returned ${HTTP_CODE}, expected 200 — body: $(body_excerpt "$HTTP_BODY")"
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
