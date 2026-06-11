#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"

echo -e "\n=== Verifying GKE Clusters ==="
gcloud container clusters list --filter="name:gke-europe-west4 OR name:gke-asia-northeast1" --project="$PROJECT_ID"

echo -e "\n=== Verifying VPC Network ==="
gcloud compute networks list --filter="name:tpu-gke-dranet-vpc" --project="$PROJECT_ID"

echo -e "\n=== Verifying Subnets and Private Google Access ==="
gcloud compute networks subnets list --filter="name:tpu-gke-dranet-node-subnet" --project="$PROJECT_ID" \
  --format="table(name,region,ipCidrRange,privateIpGoogleAccess)"

echo -e "\n=== Verifying Proxy Subnets ==="
gcloud compute networks subnets list --filter="name:tpu-gke-dranet-proxy-subnet OR name:tpu-gke-dranet-regional-proxy-subnet" --project="$PROJECT_ID" \
  --format="table(name,region,ipCidrRange,purpose,role)"

echo -e "\n=== Verifying Cloud NAT ==="
for REGION in europe-west4 asia-northeast1; do
  gcloud compute routers nats list \
    --router="tpu-gke-dranet-router-${REGION}" \
    --region="$REGION" \
    --project="$PROJECT_ID"
done

echo -e "\n=== Verifying Reserved Static IPs for Gateway ==="
gcloud compute addresses list --filter="name~qwen-gateway-ip OR name~qwen-single-gateway-ip" --project="$PROJECT_ID"

echo -e "\n=== Verifying GCS Bucket ==="
gcloud storage ls | grep "${PROJECT_ID}-qwen-weights"

echo -e "\n=== Verifying GCS FUSE Service Account ==="
gcloud iam service-accounts list --filter="email:gcs-fuse-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID"

echo -e "\n=== Verifying Fleet Multi-cluster Features ==="
gcloud container fleet multi-cluster-services describe --project="$PROJECT_ID" || true
gcloud container fleet ingress describe --project="$PROJECT_ID" || true
