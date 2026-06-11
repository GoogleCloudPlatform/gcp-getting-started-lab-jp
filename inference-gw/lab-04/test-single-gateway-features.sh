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

echo
echo "Current qwen-server pods:"
kubectl get pods -l app=qwen-server --context="$SINGLE_CTX" -o wide

echo
echo "For deeper KV-cache inspection, compare /metrics on each pod or run lab-03/regional-distribution-test.sh after the multi-cluster Gateway is ready."
