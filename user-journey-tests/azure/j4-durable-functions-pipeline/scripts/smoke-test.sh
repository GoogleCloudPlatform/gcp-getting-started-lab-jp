#!/usr/bin/env bash
# smoke-test.sh — acceptance test for azure/j4-durable-functions-pipeline.
# -----------------------------------------------------------------------------
# Usage: ./scripts/smoke-test.sh [azure|gcp]        (default: azure)
#
# This estate has no HTTP edge, so there is no BASE_URL to pass. Work enters the
# pipeline when a claim document lands in intake storage, and the same three
# assertions describe a healthy pipeline on either cloud:
#
#   1. a claim document can be written to intake storage
#   2. a claim state row appears for that claim within the polling window
#   3. the review queue's dead-letter store is empty
#
# The Azure branch drives those with `az`; the GCP branch drives the same three
# with `gcloud`, reading the target's resource names from the environment so
# this script does not have to know how the migration named things:
#
#   GCP_PROJECT                  required in gcp mode
#   GCP_INTAKE_BUCKET            default dfp-intake-${GCP_PROJECT}
#   GCP_CLAIM_STATE_BACKEND      the store claim state was migrated onto (default firestore)
#   GCP_CLAIM_STATE_TABLE        default claimstate — collection or table name
#   GCP_BIGTABLE_INSTANCE        required when the backend is bigtable
#   GCP_REVIEW_DLQ_SUBSCRIPTION  default dfp-claims-review-dlq
#
# Exits nonzero if any check fails.
# -----------------------------------------------------------------------------

set -uo pipefail

PROVIDER="${1:-azure}"
case "$PROVIDER" in
  azure | gcp) ;;
  *)
    echo "usage: $0 [azure|gcp]" >&2
    exit 2
    ;;
esac

RESOURCE_GROUP="dfp-rg"
INTAKE_CONTAINER="intake"
CLAIM_STATE_TABLE="claimstate"
REVIEW_QUEUE="claims-review"
POLL_ATTEMPTS=30
POLL_INTERVAL=6

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

# A claim reference the branch scanners' naming contract accepts, unique enough
# that re-running does not collide with the previous run's row.
CLAIM_REF="DFP-$(date -u +%Y)-9$(printf '%03d' $((RANDOM % 1000)))"
# The claim's receipt date is the UTC date the document lands, which is what the
# pipeline stores as the partition key.
RECEIPT_DATE="$(date -u +%F)"
CLAIM_AMOUNT_JPY=120000
CLAIM_FILE="${CLAIM_REF}_EAST_${CLAIM_AMOUNT_JPY}.pdf"
# Below the escalation threshold, so the expected resting state is the adjuster
# desk rather than the approval chain.
EXPECTED_STATE="with-adjuster"

WORK_FILE="${TMPDIR:-/tmp}/${CLAIM_FILE}"
trap 'rm -f "$WORK_FILE"' EXIT
printf '%%PDF-1.4 acceptance check for %s\n' "$CLAIM_REF" >"$WORK_FILE"

echo "Smoke-testing azure/j4-durable-functions-pipeline against ${PROVIDER} with claim ${CLAIM_REF}"
echo ""

# =============================================================================
# Azure
# =============================================================================
if [[ "$PROVIDER" == "azure" ]]; then
  # The guard is fatal the moment we are pointed at a subscription that is not
  # the lab one, and advisory when there is no Azure context at all.
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

  if [[ "$AZURE_CONTEXT" -ne 1 ]]; then
    skip "every check (no ${RESOURCE_GROUP} in the current subscription)"
  else
    STORAGE_ACCOUNT=$(az storage account list --resource-group "$RESOURCE_GROUP" \
      --query "[?starts_with(name, 'dfpclaims')].name | [0]" -o tsv 2>/dev/null || echo "")
    SB_NAMESPACE=$(az servicebus namespace list --resource-group "$RESOURCE_GROUP" \
      --query "[0].name" -o tsv 2>/dev/null || echo "")

    if [[ -z "$STORAGE_ACCOUNT" ]]; then
      fail "no claims storage account found in ${RESOURCE_GROUP}"
    else
      pass "claims storage account ${STORAGE_ACCOUNT} exists"

      TLS=$(az storage account show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT" \
        --query "minimumTlsVersion" -o tsv 2>/dev/null || echo "")
      if [[ "$TLS" == "TLS1_2" ]]; then
        pass "claims storage minimumTlsVersion is TLS1_2"
      else
        fail "claims storage minimumTlsVersion was '${TLS}', expected TLS1_2"
      fi

      # Data-plane calls read the key from the environment rather than a command
      # line, so it never reaches the process table and is never printed.
      export AZURE_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
      AZURE_STORAGE_KEY=$(az storage account keys list --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" --query "[0].value" -o tsv 2>/dev/null || echo "")
      export AZURE_STORAGE_KEY

      # Clear any row this reference left behind on an earlier run, so check 2
      # cannot pass on a stale row while the pipeline is dead.
      az storage entity delete --table-name "$CLAIM_STATE_TABLE" \
        --partition-key "$RECEIPT_DATE" --row-key "$CLAIM_REF" --if-match '*' \
        --only-show-errors --output none 2>/dev/null || true

      # ---- 1. a claim document reaches intake storage -----------------------
      if az storage blob upload --container-name "$INTAKE_CONTAINER" \
        --name "$CLAIM_FILE" --file "$WORK_FILE" --overwrite --only-show-errors \
        --output none 2>/dev/null; then
        pass "claim document ${CLAIM_FILE} written to the ${INTAKE_CONTAINER} container"
      else
        fail "could not write ${CLAIM_FILE} to the ${INTAKE_CONTAINER} container"
      fi

      # ---- 2. a claim state row appears for it ------------------------------
      OBSERVED_STATE=""
      for _ in $(seq 1 "$POLL_ATTEMPTS"); do
        OBSERVED_STATE=$(az storage entity query --table-name "$CLAIM_STATE_TABLE" \
          --filter "PartitionKey eq '${RECEIPT_DATE}' and RowKey eq '${CLAIM_REF}'" \
          --num-results 1 \
          --query "items[0].state" -o tsv --only-show-errors 2>/dev/null || echo "")
        [[ -n "$OBSERVED_STATE" && "$OBSERVED_STATE" != "None" ]] && break
        sleep "$POLL_INTERVAL"
      done

      if [[ "$OBSERVED_STATE" == "$EXPECTED_STATE" ]]; then
        pass "claim state row for ${CLAIM_REF} reached '${EXPECTED_STATE}'"
      elif [[ -n "$OBSERVED_STATE" && "$OBSERVED_STATE" != "None" ]]; then
        fail "claim state row for ${CLAIM_REF} was '${OBSERVED_STATE}', expected '${EXPECTED_STATE}'"
      else
        fail "no claim state row for ${CLAIM_REF} after $((POLL_ATTEMPTS * POLL_INTERVAL))s"
      fi
    fi

    # ---- 3. the review queue's dead-letter store is empty -------------------
    if [[ -z "$SB_NAMESPACE" ]]; then
      fail "no Service Bus namespace found in ${RESOURCE_GROUP}"
    else
      DLQ_COUNT=$(az servicebus queue show --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$SB_NAMESPACE" --name "$REVIEW_QUEUE" \
        --query "countDetails.deadLetterMessageCount" -o tsv 2>/dev/null || echo "")
      if [[ "$DLQ_COUNT" == "0" ]]; then
        pass "review queue dead-letter store is empty"
      elif [[ -z "$DLQ_COUNT" ]]; then
        fail "could not read the dead-letter count for ${REVIEW_QUEUE}"
      else
        fail "review queue dead-letter store holds ${DLQ_COUNT} messages, expected 0"
      fi
    fi
  fi
fi

# =============================================================================
# GCP
# =============================================================================
if [[ "$PROVIDER" == "gcp" ]]; then
  if ! command -v gcloud >/dev/null 2>&1; then
    skip "every check (gcloud is not on PATH)"
  elif [[ -z "${GCP_PROJECT:-}" ]]; then
    skip "every check (GCP_PROJECT is not set)"
  else
    INTAKE_BUCKET="${GCP_INTAKE_BUCKET:-dfp-intake-${GCP_PROJECT}}"
    CLAIM_STATE_BACKEND="${GCP_CLAIM_STATE_BACKEND:-firestore}"
    GCP_CLAIM_STATE_TABLE="${GCP_CLAIM_STATE_TABLE:-claimstate}"
    REVIEW_DLQ_SUBSCRIPTION="${GCP_REVIEW_DLQ_SUBSCRIPTION:-dfp-claims-review-dlq}"

    # ---- 1. a claim document reaches intake storage -----------------------
    if gcloud storage cp "$WORK_FILE" "gs://${INTAKE_BUCKET}/${CLAIM_FILE}" \
      --project "$GCP_PROJECT" --quiet >/dev/null 2>&1; then
      pass "claim document ${CLAIM_FILE} written to gs://${INTAKE_BUCKET}"
    else
      fail "could not write ${CLAIM_FILE} to gs://${INTAKE_BUCKET}"
    fi

    # ---- 2. a claim state row appears for it ------------------------------
    # The claim state store is whichever datastore the migration landed on, so
    # read it through the backend named in the environment.
    read_claim_state() {
      case "$CLAIM_STATE_BACKEND" in
        firestore)
          local url="https://firestore.googleapis.com/v1/projects/${GCP_PROJECT}/databases/(default)/documents/${GCP_CLAIM_STATE_TABLE}/${CLAIM_REF}"
          curl -sS --max-time 20 -H "Authorization: Bearer ${ACCESS_TOKEN}" "$url" 2>/dev/null |
            python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("fields",{}).get("state",{}).get("stringValue",""))' 2>/dev/null
          ;;
        bigtable)
          cbt -project "$GCP_PROJECT" -instance "$GCP_BIGTABLE_INSTANCE" \
            lookup "$GCP_CLAIM_STATE_TABLE" "$CLAIM_REF" 2>/dev/null |
            awk '/"state"/{getline; gsub(/^[ \t]+|[ \t]+$/, "", $0); print; exit}'
          ;;
        *) echo "" ;;
      esac
    }

    OBSERVED_STATE=""
    ACCESS_TOKEN=""
    if [[ "$CLAIM_STATE_BACKEND" == "firestore" ]]; then
      ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null || echo "")
    fi

    if [[ "$CLAIM_STATE_BACKEND" == "firestore" && -z "$ACCESS_TOKEN" ]]; then
      fail "could not obtain a GCP access token to read claim state"
    elif [[ "$CLAIM_STATE_BACKEND" == "bigtable" ]] && ! command -v cbt >/dev/null 2>&1; then
      skip "claim state check (backend is bigtable and cbt is not on PATH)"
    elif [[ "$CLAIM_STATE_BACKEND" == "bigtable" && -z "${GCP_BIGTABLE_INSTANCE:-}" ]]; then
      fail "GCP_CLAIM_STATE_BACKEND=bigtable but GCP_BIGTABLE_INSTANCE is not set"
    elif [[ "$CLAIM_STATE_BACKEND" != "firestore" && "$CLAIM_STATE_BACKEND" != "bigtable" ]]; then
      fail "GCP_CLAIM_STATE_BACKEND='${CLAIM_STATE_BACKEND}' is not one of firestore|bigtable"
    else
      for _ in $(seq 1 "$POLL_ATTEMPTS"); do
        OBSERVED_STATE=$(read_claim_state)
        [[ -n "$OBSERVED_STATE" ]] && break
        sleep "$POLL_INTERVAL"
      done

      if [[ "$OBSERVED_STATE" == "$EXPECTED_STATE" ]]; then
        pass "claim state row for ${CLAIM_REF} reached '${EXPECTED_STATE}'"
      elif [[ -n "$OBSERVED_STATE" ]]; then
        fail "claim state row for ${CLAIM_REF} was '${OBSERVED_STATE}', expected '${EXPECTED_STATE}'"
      else
        fail "no claim state row for ${CLAIM_REF} after $((POLL_ATTEMPTS * POLL_INTERVAL))s"
      fi
    fi

    # ---- 3. the review queue's dead-letter store is empty -------------------
    DLQ_MESSAGE=$(gcloud pubsub subscriptions pull "$REVIEW_DLQ_SUBSCRIPTION" \
      --project "$GCP_PROJECT" --limit=1 --format='value(message.messageId)' 2>/dev/null || echo "__unreadable__")
    if [[ "$DLQ_MESSAGE" == "__unreadable__" ]]; then
      fail "could not read the dead-letter subscription ${REVIEW_DLQ_SUBSCRIPTION}"
    elif [[ -z "$DLQ_MESSAGE" ]]; then
      pass "review queue dead-letter store is empty"
    else
      fail "review queue dead-letter store holds at least one message (${DLQ_MESSAGE})"
    fi
  fi
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
