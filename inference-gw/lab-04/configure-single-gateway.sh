#!/bin/bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
SINGLE_GATEWAY_REGION="${SINGLE_GATEWAY_REGION:-asia-northeast1}"
SINGLE_GATEWAY_ZONE="${SINGLE_GATEWAY_ZONE:-asia-northeast1-b}"
SINGLE_GATEWAY_CLUSTER="${SINGLE_GATEWAY_CLUSTER:-gke-asia-northeast1}"
SINGLE_CTX="${SINGLE_CTX:-gke_${PROJECT_ID}_${SINGLE_GATEWAY_ZONE}_${SINGLE_GATEWAY_CLUSTER}}"
ENABLE_BBR="${ENABLE_BBR:-false}"
BBR_CHART_VERSION="${BBR_CHART_VERSION:-v1.1.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATED_MANIFEST="$SCRIPT_DIR/config-single-gateway.yaml"

ensure_gateway_api() {
  echo "Ensuring Gateway API is enabled on $SINGLE_GATEWAY_CLUSTER..."
  gcloud container clusters update "$SINGLE_GATEWAY_CLUSTER" \
    --location="$SINGLE_GATEWAY_ZONE" \
    --gateway-api=standard \
    --project="$PROJECT_ID" \
    --quiet

  gcloud container clusters get-credentials "$SINGLE_GATEWAY_CLUSTER" \
    --location="$SINGLE_GATEWAY_ZONE" \
    --project="$PROJECT_ID"
}

ensure_inference_pool() {
  if kubectl get inferencepool qwen-pool --context="$SINGLE_CTX" >/dev/null 2>&1; then
    return
  fi

  echo "ERROR: InferencePool qwen-pool was not found on $SINGLE_CTX."
  echo "Run lab-02/configure-inference-api.sh first, then retry this script."
  exit 1
}

install_body_based_router() {
  local helm_args

  echo "Installing Body-Based Routing extension for single-inference-gateway..."
  helm_args=(
    upgrade --install body-based-router
    --kube-context "$SINGLE_CTX"
    --set provider.name=gke
    --set inferenceGateway.name=single-inference-gateway
    --version "$BBR_CHART_VERSION"
  )

  helm "${helm_args[@]}" \
    oci://registry.k8s.io/gateway-api-inference-extension/charts/body-based-routing

  echo "Switching HTTPRoute to require the X-Gateway-Model-Name header injected from request body..."
  kubectl apply -f "$SCRIPT_DIR/body-routing-route.yaml" --context="$SINGLE_CTX"
}

ensure_gateway_api
ensure_inference_pool

echo "Rendering single-cluster Gateway manifest..."
export SINGLE_GATEWAY_REGION
envsubst '${SINGLE_GATEWAY_REGION}' < "$SCRIPT_DIR/config-single-gateway_template.yaml" > "$GENERATED_MANIFEST"

echo "Applying single-cluster Gateway resources..."
kubectl apply -f "$GENERATED_MANIFEST" --context="$SINGLE_CTX"

if [[ "$ENABLE_BBR" == "true" ]]; then
  install_body_based_router
else
  echo "Body-Based Routing is disabled. Set ENABLE_BBR=true to test model-name extraction from request bodies."
fi

echo "Waiting for single-inference-gateway to be programmed..."
if ! kubectl wait --for=condition=programmed gateway/single-inference-gateway --timeout=10m --context="$SINGLE_CTX"; then
  echo "ERROR: single-inference-gateway did not become programmed within 10 minutes."
  kubectl describe gateway single-inference-gateway --context="$SINGLE_CTX" || true
  kubectl describe httproute single-qwen-route --context="$SINGLE_CTX" || true
  exit 1
fi

echo
echo "Single-cluster Gateway is ready."
kubectl get gateway single-inference-gateway --context="$SINGLE_CTX" -o wide
