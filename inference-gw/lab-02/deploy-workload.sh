#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"
: "${CTX_EU:?Set CTX_EU before running this script.}"
: "${CTX_ASIA:?Set CTX_ASIA before running this script.}"

replicas_for_context() {
  local ctx="$1"

  case "$ctx" in
    *europe-west4*)
      printf "%s" "${VLLM_REPLICAS_EU:-2}"
      ;;
    *asia-northeast1*)
      printf "%s" "${VLLM_REPLICAS_ASIA:-1}"
      ;;
    *)
      printf "%s" "${VLLM_REPLICAS_DEFAULT:-1}"
      ;;
  esac
}

for CTX in $CTX_EU $CTX_ASIA; do
  ZONE=$(echo "$CTX" | cut -d_ -f3)
  CLUSTER=$(echo "$CTX" | cut -d_ -f4)
  REPLICAS="$(replicas_for_context "$CTX")"
  gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project="$PROJECT_ID"

  kubectl apply -f workload.yaml --context="$CTX"
  kubectl scale deployment/vllm-qwen --replicas="$REPLICAS" --context="$CTX"
  echo "Set vllm-qwen replicas to ${REPLICAS} on ${CTX}."
done
