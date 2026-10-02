#!/usr/bin/env bash
# 00-vars.sh — shared variables for the j5-eks-microservices GCP reference.
set -euo pipefail

export GCP_PROJECT="${GCP_PROJECT:-aws-migration-501814}"
export GCP_REGION="${GCP_REGION:-asia-northeast1}"
export CLUSTER="ems-cluster"
export AR_REPO="ems"
export AR_PREFIX="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${AR_REPO}"
export IMAGE_TAG="${IMAGE_TAG:-latest}"
export FIRESTORE_DB="ems-bookings"
export GSA_NAME="ems-booking-gsa"
export GSA_EMAIL="${GSA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
export K8S_NAMESPACE="ems"
export KSA_NAME="booking-api"

echo "project=${GCP_PROJECT} region=${GCP_REGION} cluster=${CLUSTER} ar=${AR_PREFIX}"
