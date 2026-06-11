#!/bin/bash
set -euo pipefail

export PROJECT_ID=$(gcloud config get-value project)
export CTX_EU="gke_${PROJECT_ID}_europe-west4-a_gke-europe-west4"
export CTX_ASIA="gke_${PROJECT_ID}_asia-northeast1-b_gke-asia-northeast1"

echo -e "\n=== PHASE 1: VERIFYING CURRENT STATE (BOTH CLUSTERS UP) ==="
echo "Checking Asia Cluster (Primary):"
kubectl get pods -l app=qwen-server --context="$CTX_ASIA"
echo "Checking EU Cluster (Secondary):"
kubectl get pods -l app=qwen-server --context="$CTX_EU"

echo -e "\nDeploying Test Client in Asia..."
export GATEWAY_IP_ASIA=$(gcloud compute addresses describe qwen-gateway-ip-asia-northeast1 --region=asia-northeast1 --project="$PROJECT_ID" --format="value(address)")

kubectl run curl-test --image=curlimages/curl --restart=Never --context="$CTX_ASIA" -- sleep 3600
kubectl wait --for=condition=ready pod/curl-test --context="$CTX_ASIA" --timeout=60s

echo -e "\n=== PHASE 2: BASELINE TEST (Asia Client -> Asia TPUs) ==="
echo "Prompting the AI: 'What is the capital of France?'"
echo "Expect to see the full JSON response including token usage..."
kubectl exec curl-test --context="$CTX_ASIA" -- curl -s -X POST "http://$GATEWAY_IP_ASIA/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-8B",
    "messages": [{"role": "user", "content": "What is the capital of France?"}],
    "max_tokens": 100
  }' | jq .

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

echo -e "\n=== PHASE 6: FAILOVER TEST (Asia Client -> EU TPUs) ==="
echo "Prompting the AI: 'What is the capital of Germany?'"
echo "Request is actively being rerouted to Europe. Expecting full JSON response..."
kubectl exec curl-test --context="$CTX_ASIA" -- curl -s -X POST "http://$GATEWAY_IP_ASIA/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-8B",
    "messages": [{"role": "user", "content": "What is the capital of Germany?"}],
    "max_tokens": 100
  }' | jq .

echo -e "\n=== PHASE 7: RESTORING INFRASTRUCTURE (Scaling Asia to 2) ==="
kubectl scale deployment vllm-qwen --replicas=2 --context="$CTX_ASIA"
echo "Waiting for Asia pods to boot and mount FUSE..."
kubectl rollout status deployment/vllm-qwen --timeout=15m --context="$CTX_ASIA"

echo -e "\n=== PHASE 8: CONFIRMING BOTH SYSTEMS ARE BACK UP ==="
echo "Checking Asia Cluster (Restored):"
kubectl get pods -l app=qwen-server --context="$CTX_ASIA"
echo "Checking EU Cluster (Still Healthy):"
kubectl get pods -l app=qwen-server --context="$CTX_EU"

echo -e "\n=== PHASE 9: CLEANUP ==="
kubectl delete pod curl-test --context="$CTX_ASIA"
echo "Failover lab complete."
