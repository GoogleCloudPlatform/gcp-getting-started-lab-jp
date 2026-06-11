#!/bin/bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
CTX_EU="${CTX_EU:-gke_${PROJECT_ID}_europe-west4-a_gke-europe-west4}"
CTX_ASIA="${CTX_ASIA:-gke_${PROJECT_ID}_asia-northeast1-b_gke-asia-northeast1}"

REQUESTS_PER_REGION="${REQUESTS_PER_REGION:-4}"
MAX_TOKENS="${MAX_TOKENS:-24}"
CURL_TIMEOUT="${CURL_TIMEOUT:-180}"
CLIENT_POD="${CLIENT_POD:-curl-regional-test}"
MODEL_NAME="${MODEL_NAME:-Qwen/Qwen3-8B}"
PROMPT_PREFIX="${PROMPT_PREFIX:-Regional distribution check. Reply with one short sentence.}"

tmp_dir="$(mktemp -d)"
before_file="$tmp_dir/before.psv"
after_file="$tmp_dir/after.psv"

cleanup() {
  rm -rf "$tmp_dir"
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

  kubectl wait --for=condition=Ready "pod/$CLIENT_POD" --context="$ctx" --timeout=90s
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

snapshot_cluster() {
  local ctx="$1"
  local region="$2"
  local output_file="$3"
  local pods pod_name pod_ip metrics request_field request_metric request_value kv waiting running

  pods="$(kubectl get pods \
    -l app=qwen-server \
    --field-selector=status.phase=Running \
    --context="$ctx" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}')"

  if [[ -z "$pods" ]]; then
    echo "WARN: no running qwen-server pods found in $region ($ctx)" >&2
    return
  fi

  while read -r pod_name pod_ip; do
    [[ -z "$pod_name" ]] && continue

    metrics="$(kubectl exec "$CLIENT_POD" --context="$ctx" -- \
      curl -fsS --max-time 10 "http://${pod_ip}:8000/metrics" 2>/dev/null || true)"

    if [[ -z "$metrics" ]]; then
      printf "%s|%s|%s|unreachable|0|0|0|0\n" "$region" "$pod_name" "$pod_ip" >>"$output_file"
      continue
    fi

    request_field="$(first_metric "$metrics")"
    request_metric="${request_field%%|*}"
    request_value="${request_field#*|}"
    kv="$(kv_metric "$metrics")"
    waiting="$(metric_or_zero "$metrics" "vllm:num_requests_waiting")"
    running="$(metric_or_zero "$metrics" "vllm:num_requests_running")"

    printf "%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$region" "$pod_name" "$pod_ip" "$request_metric" "$request_value" "$kv" "$waiting" "$running" \
      >>"$output_file"
  done <<<"$pods"
}

snapshot_all() {
  local output_file="$1"
  : >"$output_file"
  snapshot_cluster "$CTX_ASIA" "asia-northeast1" "$output_file"
  snapshot_cluster "$CTX_EU" "europe-west4" "$output_file"
}

post_requests() {
  local ctx="$1"
  local region="$2"
  local gateway_ip="$3"
  local i payload pids pid failed

  pids=""
  failed=0

  i=1
  while [[ "$i" -le "$REQUESTS_PER_REGION" ]]; do
    payload="$(printf '{"model":"%s","messages":[{"role":"user","content":"%s Region=%s Request=%s"}],"max_tokens":%s,"temperature":0}' \
      "$MODEL_NAME" "$PROMPT_PREFIX" "$region" "$i" "$MAX_TOKENS")"

    (
      kubectl exec "$CLIENT_POD" --context="$ctx" -- \
        curl -fsS --max-time "$CURL_TIMEOUT" -o /dev/null \
        -X POST "http://${gateway_ip}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "$payload" || {
          echo "WARN: request $i from $region failed" >&2
          exit 1
        }
    ) &
    pids="$pids $!"
    i=$((i + 1))
  done

  for pid in $pids; do
    if ! wait "$pid"; then
      failed=1
    fi
  done

  return "$failed"
}

print_delta() {
  awk -F'|' '
    NR == FNR {
      key = $1 SUBSEP $2
      before_value[key] = $5
      before_kv[key] = $6
      next
    }
    {
      key = $1 SUBSEP $2
      start = (key in before_value) ? before_value[key] : 0
      start_kv = (key in before_kv) ? before_kv[key] : "0"
      delta = $5 - start
      total[$1] += delta
      printf "%-17s %-42s %-36s delta=%8.2f kv=%s->%s waiting=%s running=%s\n", $1, $2, $4, delta, start_kv, $6, $7, $8
    }
    END {
      print ""
      print "Cluster totals:"
      for (region in total) {
        printf "  %-17s delta=%8.2f\n", region, total[region]
      }
    }
  ' "$before_file" "$after_file"
}

echo "Preparing curl clients..."
ensure_client "$CTX_ASIA"
ensure_client "$CTX_EU"

GATEWAY_IP_ASIA="${GATEWAY_IP_ASIA:-$(gcloud compute addresses describe qwen-gateway-ip-asia-northeast1 --region=asia-northeast1 --project="$PROJECT_ID" --format='value(address)')}"
GATEWAY_IP_EU="${GATEWAY_IP_EU:-$(gcloud compute addresses describe qwen-gateway-ip-europe-west4 --region=europe-west4 --project="$PROJECT_ID" --format='value(address)')}"

echo
echo "Taking metric snapshot before traffic..."
snapshot_all "$before_file"

echo
echo "Sending ${REQUESTS_PER_REGION} concurrent requests from each region..."
post_requests "$CTX_ASIA" "asia-northeast1" "$GATEWAY_IP_ASIA" &
pid_asia=$!
post_requests "$CTX_EU" "europe-west4" "$GATEWAY_IP_EU" &
pid_eu=$!

failed=0
wait "$pid_asia" || failed=1
wait "$pid_eu" || failed=1

sleep 5

echo
echo "Taking metric snapshot after traffic..."
snapshot_all "$after_file"

echo
echo "=== Regional distribution result ==="
print_delta

if [[ "$failed" -ne 0 ]]; then
  echo
  echo "One or more requests failed. Check Gateway, HTTPRoute, and backend health before trusting the distribution numbers."
  exit 1
fi

echo
echo "If deltas appear in both regions, requests reached both regional backend pools."
echo "Reading the table: delta is the increase in successful vLLM requests per pod during this run."
echo "A kv value of 0.000000 is OK for short prompts; this check is mainly for regional reachability."
echo "For a stronger signal, rerun with REQUESTS_PER_REGION=10 MAX_TOKENS=16."
