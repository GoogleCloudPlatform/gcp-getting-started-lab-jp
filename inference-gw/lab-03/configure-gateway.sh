#!/bin/bash
set -euo pipefail

: "${CTX_ASIA:?Set CTX_ASIA before running this script.}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
GATEWAY_CLASS="gke-l7-cross-regional-internal-managed-mc"
CONFIG_CLUSTER="${CONFIG_CLUSTER:-gke-asia-northeast1}"
CONFIG_CLUSTER_LOCATION="${CONFIG_CLUSTER_LOCATION:-asia-northeast1-b}"
CONFIG_MEMBERSHIP_LOCATION="${CONFIG_MEMBERSHIP_LOCATION:-asia-northeast1}"
CONFIG_MEMBERSHIP="${CONFIG_MEMBERSHIP:-}"

if [[ -z "$CONFIG_MEMBERSHIP" ]]; then
  CONFIG_MEMBERSHIP=$(
    gcloud container fleet memberships list \
      --project="$PROJECT_ID" \
      --format="value(name)" | grep "/locations/${CONFIG_MEMBERSHIP_LOCATION}/memberships/${CONFIG_CLUSTER}$" | head -n 1 || true
  )
fi
CONFIG_MEMBERSHIP="${CONFIG_MEMBERSHIP:-projects/${PROJECT_ID}/locations/${CONFIG_MEMBERSHIP_LOCATION}/memberships/${CONFIG_CLUSTER}}"

diagnose_gateway() {
  echo
  echo "=== Gateway diagnostics ==="
  kubectl get gateway cross-region-gateway --context="$CTX_ASIA" -o wide || true
  kubectl describe gateway cross-region-gateway --context="$CTX_ASIA" || true
  kubectl get gatewayclasses --context="$CTX_ASIA" || true
  kubectl get gcpinferencepoolimports.networking.gke.io --context="$CTX_ASIA" || true
  gcloud container fleet multi-cluster-services describe --project="$PROJECT_ID" || true
  gcloud container fleet ingress describe --project="$PROJECT_ID" || true
}

ensure_fleet_connectivity() {
  local fleet_state
  fleet_state="$(mktemp)"
  {
    gcloud container fleet multi-cluster-services describe --project="$PROJECT_ID" || true
    gcloud container fleet ingress describe --project="$PROJECT_ID" || true
  } >"$fleet_state" 2>&1

  if grep -q "description: Lost connection" "$fleet_state"; then
    echo "Fleet reports Lost connection for one or more memberships."
    echo "Repairing Fleet memberships by installing/updating the Connect agent..."
    PROJECT_ID="$PROJECT_ID" "$LAB_DIR/lab-01/repair-fleet-memberships.sh"
    CONFIG_MEMBERSHIP="projects/${PROJECT_ID}/locations/${CONFIG_MEMBERSHIP_LOCATION}/memberships/${CONFIG_CLUSTER}"
  fi

  rm -f "$fleet_state"
}

ensure_fleet_gateway_iam() {
  local project_number
  local mci_service_agent
  local role

  project_number="$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")"
  mci_service_agent="service-${project_number}@gcp-sa-multiclusteringress.iam.gserviceaccount.com"

  echo "Ensuring Multi Cluster Ingress service agent can manage GKE..."
  for role in roles/container.admin roles/multiclusteringress.serviceAgent; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${mci_service_agent}" \
      --role="$role" \
      --condition=None \
      --quiet >/dev/null
  done
}

ensure_gateway_api() {
  echo "Ensuring Gateway API is enabled on the config cluster..."
  gcloud container clusters update "$CONFIG_CLUSTER" \
    --location="$CONFIG_CLUSTER_LOCATION" \
    --gateway-api=standard \
    --project="$PROJECT_ID" \
    --quiet
  gcloud container clusters get-credentials "$CONFIG_CLUSTER" \
    --location="$CONFIG_CLUSTER_LOCATION" \
    --project="$PROJECT_ID"
}

ensure_gateway_class() {
  if kubectl get gatewayclass "$GATEWAY_CLASS" --context="$CTX_ASIA" >/dev/null 2>&1; then
    return
  fi

  echo "GatewayClass $GATEWAY_CLASS is not present on the config cluster."
  if kubectl get gateway cross-region-gateway --context="$CTX_ASIA" >/dev/null 2>&1; then
    echo "Deleting stale Gateway resources before resetting Fleet ingress..."
    kubectl delete -f "$SCRIPT_DIR/config-cluster.yaml" --context="$CTX_ASIA" --ignore-not-found || true
  fi

  echo "Re-enabling Fleet ingress for $CONFIG_MEMBERSHIP..."
  gcloud container fleet ingress disable --project="$PROJECT_ID" --quiet || true

  if ! gcloud container fleet ingress enable \
    --config-membership="$CONFIG_MEMBERSHIP" \
    --project="$PROJECT_ID" \
    --quiet; then
    echo "Fleet ingress enable did not observe the controller within the gcloud 2 minute wait."
    echo "Continuing to poll GatewayClass because config cluster registration can take longer."
    gcloud container fleet ingress describe --project="$PROJECT_ID" || true
  fi

  echo "Waiting for GatewayClass $GATEWAY_CLASS to appear..."
  for _ in {1..90}; do
    if kubectl get gatewayclass "$GATEWAY_CLASS" --context="$CTX_ASIA" >/dev/null 2>&1; then
      kubectl get gatewayclass "$GATEWAY_CLASS" --context="$CTX_ASIA"
      return
    fi
    sleep 10
  done

  echo "ERROR: GatewayClass $GATEWAY_CLASS did not appear after re-enabling Fleet ingress."
  diagnose_gateway
  exit 1
}

ensure_inference_pool_import() {
  if kubectl get gcpinferencepoolimports.networking.gke.io qwen-pool --context="$CTX_ASIA" >/dev/null 2>&1; then
    return
  fi

  echo "GCPInferencePoolImport qwen-pool is not present yet. Waiting for the export to sync..."
  for _ in {1..90}; do
    if kubectl get gcpinferencepoolimports.networking.gke.io qwen-pool --context="$CTX_ASIA" >/dev/null 2>&1; then
      kubectl get gcpinferencepoolimports.networking.gke.io qwen-pool --context="$CTX_ASIA"
      return
    fi
    sleep 10
  done

  echo "ERROR: GCPInferencePoolImport qwen-pool was not found on the config cluster."
  echo "Run ../lab-02/configure-inference-api.sh before configuring the Gateway, then retry this script."
  exit 1
}

ensure_gateway_api
ensure_fleet_connectivity
ensure_fleet_gateway_iam
ensure_gateway_class
ensure_inference_pool_import

echo -e "\n=== Creating Cross-Regional Gateway Resources ==="
kubectl apply -f "$SCRIPT_DIR/config-cluster.yaml" --context="$CTX_ASIA"

echo -e "\n=== Provisioning Global Load Balancer (This takes 5-10 minutes) ==="
echo "Working on the Gateway... waiting for Google Cloud to assign IPs and program routes..."

if ! kubectl wait --for=condition=programmed gateway/cross-region-gateway --timeout=10m --context="$CTX_ASIA"; then
  echo "ERROR: Gateway did not become programmed within 10 minutes."
  diagnose_gateway
  exit 1
fi

echo -e "\n=== SUCCESS: Gateway is fully provisioned and ready! ==="
