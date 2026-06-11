#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"
: "${CTX_EU:?Set CTX_EU before running this script.}"
: "${CTX_ASIA:?Set CTX_ASIA before running this script.}"

for CTX in $CTX_EU $CTX_ASIA; do
  ZONE=$(echo "$CTX" | cut -d_ -f3)
  CLUSTER=$(echo "$CTX" | cut -d_ -f4)
  gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project="$PROJECT_ID"

  kubectl apply -f workload.yaml --context="$CTX"
done
