#!/bin/bash
set -euo pipefail

: "${LORA_NAME:?Set LORA_NAME to the model name exposed by the adapter.}"
: "${LORA_PATH:?Set LORA_PATH to a path visible from the vLLM container, for example /data/lora/my-adapter.}"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
SINGLE_GATEWAY_REGION="${SINGLE_GATEWAY_REGION:-asia-northeast1}"
SINGLE_GATEWAY_ZONE="${SINGLE_GATEWAY_ZONE:-asia-northeast1-b}"
SINGLE_GATEWAY_CLUSTER="${SINGLE_GATEWAY_CLUSTER:-gke-asia-northeast1}"
SINGLE_CTX="${SINGLE_CTX:-gke_${PROJECT_ID}_${SINGLE_GATEWAY_ZONE}_${SINGLE_GATEWAY_CLUSTER}}"
CLIENT_POD="${CLIENT_POD:-curl-single-gateway-test}"
TARGET_URL="${TARGET_URL:-http://vllm-qwen-service.default.svc.cluster.local:8000}"
MAX_TOKENS="${MAX_TOKENS:-32}"
CURL_TIMEOUT="${CURL_TIMEOUT:-180}"

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

json_escape() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

print_lora_help() {
  echo
  echo "If this returns a 404 about LoRA support, redeploy vLLM with:"
  echo "  export VLLM_EXTRA_ARGS=\"--enable-lora --max-loras 4 --max-lora-rank 64\""
  echo "  export VLLM_ALLOW_RUNTIME_LORA_UPDATING=True"
  echo "  envsubst '\${PROJECT_ID} \${VLLM_EXTRA_ARGS} \${VLLM_ALLOW_RUNTIME_LORA_UPDATING}' < ../lab-02/workload_template.yaml > ../lab-02/workload.yaml"
  echo "  ../lab-02/deploy-workload.sh"
}

ensure_client

escaped_name="$(json_escape "$LORA_NAME")"
escaped_path="$(json_escape "$LORA_PATH")"

echo "Loading LoRA adapter into vLLM..."
if ! kubectl exec "$CLIENT_POD" --context="$SINGLE_CTX" -- \
  curl -sS --fail --max-time "$CURL_TIMEOUT" \
    -X POST "${TARGET_URL}/v1/load_lora_adapter" \
    -H "Content-Type: application/json" \
    -d "{\"lora_name\":\"${escaped_name}\",\"lora_path\":\"${escaped_path}\"}" | jq .; then
  echo "ERROR: LoRA adapter load failed."
  print_lora_help
  exit 1
fi

echo
echo "Testing the loaded adapter through ${TARGET_URL}..."
if ! kubectl exec "$CLIENT_POD" --context="$SINGLE_CTX" -- \
  curl -sS --fail --max-time "$CURL_TIMEOUT" \
    -X POST "${TARGET_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${escaped_name}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one short sentence.\"}],\"max_tokens\":${MAX_TOKENS},\"temperature\":0}" | jq .; then
  echo "ERROR: LoRA adapter test request failed."
  print_lora_help
  exit 1
fi

echo
echo "LoRA adapter is responding."
