#!/usr/bin/env bash
# 06-kubectl-apply.sh — render GKE manifests from the journey's k8s/ dir and
# apply them. Requires kubectl + the cluster from 01. Idempotent.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export KUBECONFIG="${HOME}/.kube/config-ems-gcp"

gcloud container clusters get-credentials "${CLUSTER}" \
  --region "${GCP_REGION}" --project "${GCP_PROJECT}"

AR_PREFIX="${AR_PREFIX}" IMAGE_TAG="${IMAGE_TAG}" GSA_EMAIL="${GSA_EMAIL}" \
GCP_PROJECT="${GCP_PROJECT}" FIRESTORE_DB="${FIRESTORE_DB}" \
  python3 "${SCRIPT_DIR}/../k8s-overlay/render.py"

kubectl apply -f "${SCRIPT_DIR}/../k8s-build/"
kubectl -n "${K8S_NAMESPACE}" rollout status deploy/catalog-api --timeout=300s
kubectl -n "${K8S_NAMESPACE}" rollout status deploy/booking-api --timeout=300s
