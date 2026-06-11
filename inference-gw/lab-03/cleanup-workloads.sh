#!/bin/bash
set -euo pipefail

echo "=== PART 1: Kubernetes & Workload Cleanup ==="
export PROJECT_ID=$(gcloud config get-value project)
export CTX_EU="gke_${PROJECT_ID}_europe-west4-a_gke-europe-west4"
export CTX_ASIA="gke_${PROJECT_ID}_asia-northeast1-b_gke-asia-northeast1"

echo "Deleting Gateway resources..."
for CTX in $CTX_EU $CTX_ASIA; do
  kubectl delete gateways,httproutes,healthcheckpolicies,gcpbackendpolicies --all --context="$CTX" --ignore-not-found
done

echo "Waiting 60 seconds for the external Load Balancer to detach..."
sleep 60

echo "Cleaning up workloads and custom resources..."
CRD_URL="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api-inference-extension/v1.1.0/config/crd/bases/inference.networking.x-k8s.io_inferenceobjectives.yaml"
for CTX in $CTX_EU $CTX_ASIA; do
  helm uninstall qwen-pool --kube-context="$CTX" || true
  kubectl delete job model-downloader --context="$CTX" --ignore-not-found
  kubectl delete all -l app=qwen-server --context="$CTX" --ignore-not-found
  kubectl delete inferenceobjectives,autoscalingmetrics --all --context="$CTX" --ignore-not-found
  kubectl delete serviceaccount qwen-ksa --context="$CTX" --ignore-not-found
  kubectl delete -f "$CRD_URL" --context="$CTX" --ignore-not-found
done

echo -e "\n=== Part 1 Complete! Safe to proceed to Terraform Teardown. ==="
