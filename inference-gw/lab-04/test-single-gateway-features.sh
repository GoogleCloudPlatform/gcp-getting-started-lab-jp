#!/bin/bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
SINGLE_GATEWAY_REGION="${SINGLE_GATEWAY_REGION:-asia-northeast1}"
SINGLE_GATEWAY_ZONE="${SINGLE_GATEWAY_ZONE:-asia-northeast1-b}"
SINGLE_GATEWAY_CLUSTER="${SINGLE_GATEWAY_CLUSTER:-gke-asia-northeast1}"
SINGLE_CTX="${SINGLE_CTX:-gke_${PROJECT_ID}_${SINGLE_GATEWAY_ZONE}_${SINGLE_GATEWAY_CLUSTER}}"
CLIENT_POD="${CLIENT_POD:-curl-single-gateway-test}"
MODEL_NAME="${MODEL_NAME:-Qwen/Qwen3-8B}"
MAX_TOKENS="${MAX_TOKENS:-32}"
CURL_TIMEOUT="${CURL_TIMEOUT:-180}"
PREFIX_ROUNDS="${PREFIX_ROUNDS:-4}"
EXPECT_BBR="${EXPECT_BBR:-false}"
PREFIX_AFFINITY_TEST="${PREFIX_AFFINITY_TEST:-false}"
PREFIX_AFFINITY_ROUNDS="${PREFIX_AFFINITY_ROUNDS:-8}"
PREFIX_AFFINITY_COMPARE_DIFFERENT="${PREFIX_AFFINITY_COMPARE_DIFFERENT:-true}"
AFFINITY_PROMPT_PREFIX="${AFFINITY_PROMPT_PREFIX:-GKE Inference Gateway prefix affinity demo 2026. This long shared prefix should make cache-aware routing easier to observe.}"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

ensure_client() {
  local phase

  phase="$(kubectl get pod "$CLIENT_POD" --context="$SINGLE_CTX" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "$phase" != "Running" ]]; then
    kubectl delete pod "$CLIENT_POD" --context="$SINGLE_CTX" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl run "$CLIENT_POD" \
      --image=curlimages/curl \
      --restart=Never \
      --context="$SINGLE_CTX" \
      -- sleep 3600
  fi

  kubectl wait --for=condition=Ready "pod/$CLIENT_POD" --context="$SINGLE_CTX" --timeout=90s
}

post_chat() {
  local model="$1"
  local prompt="$2"
  local output_file="$3"
  local payload

  payload="$(printf '{"model":"%s","messages":[{"role":"user","content":"%s"}],"max_tokens":%s,"temperature":0}' \
    "$model" "$prompt" "$MAX_TOKENS")"

  kubectl exec "$CLIENT_POD" --context="$SINGLE_CTX" -- \
    curl -sS --max-time "$CURL_TIMEOUT" \
      -o "$output_file" \
      -w "%{http_code}" \
      -X POST "http://${SINGLE_GATEWAY_IP}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "$payload"
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

first_metric() {
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

metric_or_zero() {
  local metrics="$1"
  local metric_name="$2"
  local value

  value="$(printf "%s\n" "$metrics" | metric_sum "$metric_name")"
  if [[ "$value" == "NA" ]]; then
    printf "0"
  else
    printf "%s" "$value"
  fi
}

kv_metric() {
  local metrics="$1"
  local value

  value="$(printf "%s\n" "$metrics" | metric_sum "vllm:kv_cache_usage_perc")"
  if [[ "$value" != "NA" ]]; then
    printf "%s" "$value"
    return
  fi

  value="$(printf "%s\n" "$metrics" | metric_sum "vllm:gpu_cache_usage_perc")"
  if [[ "$value" != "NA" ]]; then
    printf "%s" "$value"
    return
  fi

  printf "0"
}

snapshot_single_pods() {
  local output_file="$1"
  local pods pod_name pod_ip metrics request_field request_metric request_value kv waiting running

  : >"$output_file"
  pods="$(kubectl get pods \
    -l app=qwen-server \
    --field-selector=status.phase=Running \
    --context="$SINGLE_CTX" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}')"

  while read -r pod_name pod_ip; do
    [[ -z "$pod_name" ]] && continue

    metrics="$(kubectl exec "$CLIENT_POD" --context="$SINGLE_CTX" -- \
      curl -fsS --max-time 10 "http://${pod_ip}:8000/metrics" 2>/dev/null || true)"

    if [[ -z "$metrics" ]]; then
      printf "%s|%s|unreachable|0|0|0|0\n" "$pod_name" "$pod_ip" >>"$output_file"
      continue
    fi

    request_field="$(first_metric "$metrics")"
    request_metric="${request_field%%|*}"
    request_value="${request_field#*|}"
    kv="$(kv_metric "$metrics")"
    waiting="$(metric_or_zero "$metrics" "vllm:num_requests_waiting")"
    running="$(metric_or_zero "$metrics" "vllm:num_requests_running")"

    printf "%s|%s|%s|%s|%s|%s|%s\n" \
      "$pod_name" "$pod_ip" "$request_metric" "$request_value" "$kv" "$waiting" "$running" \
      >>"$output_file"
  done <<<"$pods"
}

print_affinity_delta() {
  local before_file="$1"
  local after_file="$2"
  local title="$3"

  echo
  echo "$title"
  awk -F'|' '
    NR == FNR {
      before_value[$1] = $4
      before_kv[$1] = $5
      next
    }
    {
      start = ($1 in before_value) ? before_value[$1] : 0
      start_kv = ($1 in before_kv) ? before_kv[$1] : "0"
      delta = $4 - start
      total += delta
      if (delta > 0) {
        active_pods += 1
      }
      printf "%-42s %-36s delta=%8.2f kv=%s->%s waiting=%s running=%s\n", $1, $3, delta, start_kv, $5, $6, $7
    }
    END {
      printf "Total delta=%8.2f active_pods=%d\n", total, active_pods
      if (active_pods == 1 && total > 1) {
        print "Observation: this batch concentrated on one pod."
      } else if (active_pods > 1) {
        print "Observation: this batch was spread across multiple pods."
      } else {
        print "Observation: no request counter increase was detected."
      }
    }
  ' "$before_file" "$after_file"
}

run_affinity_batch() {
  local mode="$1"
  local rounds="$2"
  local i prompt status

  i=1
  while [[ "$i" -le "$rounds" ]]; do
    if [[ "$mode" == "same" ]]; then
      prompt="${AFFINITY_PROMPT_PREFIX} Request ${i}. Continue with a concise but non-trivial answer about cache-aware routing."
    else
      prompt="Unique prefix ${i} $(date +%s%N). Explain one practical detail of GKE Inference Gateway routing."
    fi

    status="$(post_chat "$MODEL_NAME" "$prompt" "/tmp/single-gateway-affinity-${mode}-${i}.json")"
    echo "${mode}_prefix_round=${i} http=${status}"
    i=$((i + 1))
  done
}

run_prefix_affinity_test() {
  local pod_count same_before same_after different_before different_after

  pod_count="$(kubectl get pods \
    -l app=qwen-server \
    --field-selector=status.phase=Running \
    --context="$SINGLE_CTX" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"

  echo
  echo "=== Prefix affinity by pod delta ==="
  echo "This is an observation check, not a pass/fail assertion. Cache-aware routing can still rebalance for health or load."

  if [[ "$pod_count" -lt 2 ]]; then
    echo "Only ${pod_count} qwen-server pod is running on ${SINGLE_CTX}; same-prefix affinity is trivial."
    echo "For an interesting view, run this against the Europe cluster, which defaults to 2 vLLM pods."
    return 0
  fi

  same_before="$tmp_dir/same-before.psv"
  same_after="$tmp_dir/same-after.psv"
  snapshot_single_pods "$same_before"
  echo
  echo "Sending ${PREFIX_AFFINITY_ROUNDS} requests with the same long prefix..."
  run_affinity_batch "same" "$PREFIX_AFFINITY_ROUNDS"
  sleep 3
  snapshot_single_pods "$same_after"
  print_affinity_delta "$same_before" "$same_after" "Same-prefix batch result"

  if [[ "$PREFIX_AFFINITY_COMPARE_DIFFERENT" == "true" ]]; then
    different_before="$tmp_dir/different-before.psv"
    different_after="$tmp_dir/different-after.psv"
    snapshot_single_pods "$different_before"
    echo
    echo "Sending ${PREFIX_AFFINITY_ROUNDS} requests with different prefixes for comparison..."
    run_affinity_batch "different" "$PREFIX_AFFINITY_ROUNDS"
    sleep 3
    snapshot_single_pods "$different_after"
    print_affinity_delta "$different_before" "$different_after" "Different-prefix comparison result"
  fi
}

ensure_client

SINGLE_GATEWAY_IP="${SINGLE_GATEWAY_IP:-$(gcloud compute addresses describe "qwen-single-gateway-ip-${SINGLE_GATEWAY_REGION}" --region="$SINGLE_GATEWAY_REGION" --project="$PROJECT_ID" --format='value(address)')}"

echo "Testing single Gateway at http://${SINGLE_GATEWAY_IP}"
echo

echo "=== Base request ==="
echo "Expected: HTTP 200 from Gateway -> InferencePool -> vLLM."
status="$(post_chat "$MODEL_NAME" "Say hello in one short sentence." "/tmp/single-gateway-base.json")"
cat_status="$status"
echo "HTTP $cat_status"
if [[ "$cat_status" == "200" ]]; then
  kubectl exec "$CLIENT_POD" --context="$SINGLE_CTX" -- cat /tmp/single-gateway-base.json | jq . || true
else
  echo "WARN: expected HTTP 200. If the Gateway was just created, wait 1-3 minutes for backend health propagation and rerun this script."
  kubectl exec "$CLIENT_POD" --context="$SINGLE_CTX" -- cat /tmp/single-gateway-base.json || true
fi

if [[ "$EXPECT_BBR" == "true" ]]; then
  echo
  echo "=== Body-Based Routing negative check ==="
  echo "Expected: HTTP 404 because the route only accepts X-Gateway-Model-Name=${MODEL_NAME}."
  invalid_status="$(post_chat "not-a-routed-model" "This should not reach vLLM when BBR is active." "/tmp/single-gateway-invalid.json" || true)"
  echo "HTTP $invalid_status"
  if [[ "$invalid_status" == "404" ]]; then
    echo "BBR fail-closed check passed."
  elif [[ "$invalid_status" == "503" ]]; then
    echo "WARN: got HTTP 503. This can happen while Gateway backend health is still propagating; wait and rerun before debugging BBR."
  else
    echo "WARN: expected HTTP 404. Inspect the route and body-based-router deployment."
    kubectl exec "$CLIENT_POD" --context="$SINGLE_CTX" -- cat /tmp/single-gateway-invalid.json || true
  fi
fi

echo
echo "=== Repeated-prefix requests for KV/prefix-cache behavior ==="
echo "Expected: each round returns HTTP 200. Elapsed seconds are observational, not a strict pass/fail signal."
i=1
while [[ "$i" -le "$PREFIX_ROUNDS" ]]; do
  prompt="Use this exact repeated prefix: GKE inference gateway cache demo 2026. Round ${i}. Answer with a short fact about Tokyo."
  start="$(date +%s)"
  status="$(post_chat "$MODEL_NAME" "$prompt" "/tmp/single-gateway-prefix-${i}.json")"
  end="$(date +%s)"
  echo "round=${i} http=${status} elapsed_seconds=$((end - start))"
  i=$((i + 1))
done

if [[ "$PREFIX_AFFINITY_TEST" == "true" ]]; then
  run_prefix_affinity_test
fi

echo
echo "Current qwen-server pods:"
kubectl get pods -l app=qwen-server --context="$SINGLE_CTX" -o wide

echo
echo "For deeper KV-cache inspection, compare /metrics on each pod or run lab-03/regional-distribution-test.sh after the multi-cluster Gateway is ready."
