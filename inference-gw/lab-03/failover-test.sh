#!/bin/bash
set -euo pipefail

export PROJECT_ID=$(gcloud config get-value project)
export CTX_EU="gke_${PROJECT_ID}_europe-west4-a_gke-europe-west4"
export CTX_ASIA="gke_${PROJECT_ID}_asia-northeast1-b_gke-asia-northeast1"
export VLLM_REPLICAS_ASIA="${VLLM_REPLICAS_ASIA:-1}"
export VLLM_REPLICAS_EU="${VLLM_REPLICAS_EU:-2}"
export RESTORE_ASIA_AFTER_FAILOVER="${RESTORE_ASIA_AFTER_FAILOVER:-false}"
export CLIENT_POD="${CLIENT_POD:-curl-test}"
export MODEL_NAME="${MODEL_NAME:-Qwen/Qwen3-8B}"
export BASELINE_REQUESTS="${BASELINE_REQUESTS:-5}"
export FAILOVER_REQUESTS="${FAILOVER_REQUESTS:-5}"
export REQUEST_MAX_TOKENS="${REQUEST_MAX_TOKENS:-80}"
export CURL_TIMEOUT="${CURL_TIMEOUT:-180}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ensure_client() {
  local ctx="$1"
  local phase

  phase="$(kubectl get pod "$CLIENT_POD" --context="$ctx" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" != "Running" ]]; then
    kubectl delete pod "$CLIENT_POD" --context="$ctx" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl run "$CLIENT_POD" \
      --image=curlimages/curl \
      --restart=Never \
      --context="$ctx" \
      -- sleep 3600
  fi

  kubectl wait --for=condition=ready "pod/$CLIENT_POD" --context="$ctx" --timeout=60s
}

metric_sum() {
  local metric_name="$1"
  awk -v want="$metric_name" '
    /^#/ { next }
    {
      key = $1
      sub(/\{.*/, "", key)
      if (key == want) {
        sum += $NF
        found = 1
      }
    }
    END {
      if (found) {
        printf "%.6f", sum
      } else {
        printf "NA"
      }
    }
  '
}

first_request_counter() {
  local metrics="$1"
  local metric_name value

  for metric_name in \
    "vllm:request_success_total" \
    "vllm:e2e_request_latency_seconds_count" \
    "vllm:prompt_tokens_total" \
    "vllm:generation_tokens_total"; do
    value="$(printf "%s\n" "$metrics" | metric_sum "$metric_name")"
    if [[ "$value" != "NA" ]]; then
      printf "%s|%s" "$metric_name" "$value"
      return
    fi
  done

  printf "none|0"
}

snapshot_cluster() {
  local ctx="$1"
  local region="$2"
  local output_file="$3"
  local pods pod_name pod_ip metrics request_field request_metric request_value

  pods="$(kubectl get pods \
    -l app=qwen-server \
    --field-selector=status.phase=Running \
    --context="$ctx" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}')"

  while read -r pod_name pod_ip; do
    [[ -z "$pod_name" ]] && continue

    metrics="$(kubectl exec "$CLIENT_POD" --context="$ctx" -- \
      curl -fsS --max-time 10 "http://${pod_ip}:8000/metrics" 2>/dev/null || true)"

    if [[ -z "$metrics" ]]; then
      printf "%s|%s|unreachable|0\n" "$region" "$pod_name" >>"$output_file"
      continue
    fi

    request_field="$(first_request_counter "$metrics")"
    request_metric="${request_field%%|*}"
    request_value="${request_field#*|}"
    printf "%s|%s|%s|%s\n" "$region" "$pod_name" "$request_metric" "$request_value" >>"$output_file"
  done <<<"$pods"
}

snapshot_all() {
  local output_file="$1"

  : >"$output_file"
  snapshot_cluster "$CTX_ASIA" "asia-northeast1" "$output_file"
  snapshot_cluster "$CTX_EU" "europe-west4" "$output_file"
}

print_request_delta() {
  local before_file="$1"
  local after_file="$2"
  local title="$3"
  local expected_region="${4:-}"

  echo
  echo "$title"
  awk -F'|' -v expected_region="$expected_region" '
    NR == FNR {
      key = $1 SUBSEP $2
      before_value[key] = $4
      next
    }
    {
      key = $1 SUBSEP $2
      start = (key in before_value) ? before_value[key] : 0
      delta = $4 - start
      region_total[$1] += delta
      total += delta
      printf "%-17s %-42s %-36s delta=%8.2f\n", $1, $2, $3, delta
    }
    END {
      print ""
      print "Region totals:"
      for (region in region_total) {
        printf "  %-17s delta=%8.2f\n", region, region_total[region]
      }
      printf "  %-17s delta=%8.2f\n", "all-regions", total
      if (expected_region != "") {
        if (region_total[expected_region] > 0) {
          printf "Expected attribution observed: %s handled one or more requests.\n", expected_region
          if (region_total[expected_region] < total) {
            printf "NOTE: not all requests went to %s; compare Region totals before interpreting failover strength.\n", expected_region
          }
        } else {
          printf "WARN: expected %s to handle this request, but its delta did not increase.\n", expected_region
        }
      }
    }
  ' "$before_file" "$after_file"
}

send_chat_requests() {
  local phase="$1"
  local prompt="$2"
  local request_count="$3"
  local i payload output_file status failed

  failed=0
  i=1
  while [[ "$i" -le "$request_count" ]]; do
    output_file="/tmp/failover-${phase}-${i}.json"
    payload="$(printf '{"model":"%s","messages":[{"role":"user","content":"%s Request %s of %s."}],"max_tokens":%s,"temperature":0}' \
      "$MODEL_NAME" "$prompt" "$i" "$request_count" "$REQUEST_MAX_TOKENS")"

    if ! status="$(kubectl exec "$CLIENT_POD" --context="$CTX_ASIA" -- \
      curl -sS --max-time "$CURL_TIMEOUT" \
        -o "$output_file" \
        -w "%{http_code}" \
        -X POST "http://${GATEWAY_IP_ASIA}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "$payload")"; then
      status="curl_failed"
      failed=1
    fi

    echo "${phase}_request=${i}/${request_count} http=${status}"
    if [[ "$i" -eq 1 ]]; then
      kubectl exec "$CLIENT_POD" --context="$CTX_ASIA" -- cat "$output_file" | jq . || true
    fi
    if [[ "$status" != "200" ]]; then
      failed=1
      kubectl exec "$CLIENT_POD" --context="$CTX_ASIA" -- cat "$output_file" || true
    fi

    i=$((i + 1))
  done

  return "$failed"
}

echo -e "\n=== PHASE 1: VERIFYING CURRENT STATE (BOTH CLUSTERS UP) ==="
echo "Checking Asia Cluster (Primary):"
kubectl get pods -l app=qwen-server --context="$CTX_ASIA"
echo "Checking EU Cluster (Secondary):"
kubectl get pods -l app=qwen-server --context="$CTX_EU"

echo -e "\nDeploying curl clients for requests and metric snapshots..."
export GATEWAY_IP_ASIA=$(gcloud compute addresses describe qwen-gateway-ip-asia-northeast1 --region=asia-northeast1 --project="$PROJECT_ID" --format="value(address)")

ensure_client "$CTX_ASIA"
ensure_client "$CTX_EU"

echo -e "\n=== PHASE 2: BASELINE TEST WITH REQUEST ATTRIBUTION ==="
echo "Prompting the AI: 'What is the capital of France?'"
echo "Sending ${BASELINE_REQUESTS} baseline requests, then checking which region's vLLM counter increased..."
snapshot_all "$TMP_DIR/baseline-before.psv"
send_chat_requests "baseline" "What is the capital of France?" "$BASELINE_REQUESTS"
sleep 3
snapshot_all "$TMP_DIR/baseline-after.psv"
print_request_delta "$TMP_DIR/baseline-before.psv" "$TMP_DIR/baseline-after.psv" "Baseline request attribution (${BASELINE_REQUESTS} requests)" "asia-northeast1"

echo -e "\n=== PHASE 3: SIMULATING REGIONAL OUTAGE (Scaling Asia to 0) ==="
kubectl scale deployment vllm-qwen --replicas=0 --context="$CTX_ASIA"
echo "Waiting 20 seconds for pods to begin terminating..."
sleep 20

echo -e "\n=== PHASE 4: CONFIRMING STATE (PODS TERMINATING) ==="
echo "Checking Asia Cluster (Should be terminating):"
kubectl get pods -l app=qwen-server --context="$CTX_ASIA"
echo "Checking EU Cluster (Should still be running):"
kubectl get pods -l app=qwen-server --context="$CTX_EU"

echo -e "\nWaiting 45 seconds for Gateway health checks to update global routing tables..."
sleep 45

echo -e "\n=== PHASE 5: CONFIRMING COMPLETE DOWN AND EURO UP ==="
echo "Checking Asia Cluster (Should be completely empty now):"
kubectl get pods -l app=qwen-server --context="$CTX_ASIA"
echo "Checking EU Cluster (Should still be running):"
kubectl get pods -l app=qwen-server --context="$CTX_EU"

echo -e "\n=== PHASE 6: FAILOVER TEST WITH REQUEST ATTRIBUTION ==="
echo "Prompting the AI: 'What is the capital of Germany?'"
echo "Asia is scaled to 0. Sending ${FAILOVER_REQUESTS} requests and expecting a Europe-side counter increase..."
snapshot_all "$TMP_DIR/failover-before.psv"
send_chat_requests "failover" "What is the capital of Germany?" "$FAILOVER_REQUESTS"
sleep 3
snapshot_all "$TMP_DIR/failover-after.psv"
print_request_delta "$TMP_DIR/failover-before.psv" "$TMP_DIR/failover-after.psv" "Failover request attribution (${FAILOVER_REQUESTS} requests)" "europe-west4"

echo -e "\n=== PHASE 7: KEEPING FAILOVER STATE (Asia=0, Europe=${VLLM_REPLICAS_EU}) ==="
kubectl scale deployment vllm-qwen --replicas=0 --context="$CTX_ASIA"
kubectl scale deployment vllm-qwen --replicas="$VLLM_REPLICAS_EU" --context="$CTX_EU"
echo "Waiting for Europe pods to be ready..."
kubectl rollout status deployment/vllm-qwen --timeout=15m --context="$CTX_EU"

if [[ "$RESTORE_ASIA_AFTER_FAILOVER" == "true" ]]; then
  echo -e "\n=== PHASE 8: OPTIONAL RESTORE (Scaling Asia to ${VLLM_REPLICAS_ASIA}) ==="
  kubectl scale deployment vllm-qwen --replicas="$VLLM_REPLICAS_ASIA" --context="$CTX_ASIA"
  echo "Waiting for Asia pods to boot and mount FUSE..."
  kubectl rollout status deployment/vllm-qwen --timeout=15m --context="$CTX_ASIA"
else
  echo
  echo "Leaving Asia scaled to 0 to save TPU capacity and lab time."
  echo "To restore Asia later, run:"
  echo "  kubectl scale deployment/vllm-qwen --replicas=${VLLM_REPLICAS_ASIA} --context=\"${CTX_ASIA}\""
  echo "  kubectl rollout status deployment/vllm-qwen --timeout=15m --context=\"${CTX_ASIA}\""
fi

echo -e "\n=== PHASE 9: CONFIRMING FINAL STATE ==="
echo "Checking Asia Cluster (Should stay at 0 qwen-server pods unless RESTORE_ASIA_AFTER_FAILOVER=true):"
kubectl get pods -l app=qwen-server --context="$CTX_ASIA"
echo "Checking EU Cluster (Should have ${VLLM_REPLICAS_EU} qwen-server pods):"
kubectl get pods -l app=qwen-server --context="$CTX_EU"

echo -e "\n=== PHASE 10: CLEANUP ==="
kubectl delete pod "$CLIENT_POD" --context="$CTX_ASIA" --ignore-not-found
kubectl delete pod "$CLIENT_POD" --context="$CTX_EU" --ignore-not-found
echo "Failover lab complete."
