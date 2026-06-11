#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"
: "${CTX_EU:?Set CTX_EU before running this script.}"
: "${CTX_ASIA:?Set CTX_ASIA before running this script.}"
export PROJECT_ID
export SOURCE_MODEL_GCS_URI="${SOURCE_MODEL_GCS_URI:-}"
MODEL_BUCKET="${PROJECT_ID}-qwen-weights"
GCS_FUSE_GSA="gcs-fuse-sa@${PROJECT_ID}.iam.gserviceaccount.com"

envsubst '${PROJECT_ID}' < ksa_template.yaml > ksa.yaml
envsubst '${PROJECT_ID} ${SOURCE_MODEL_GCS_URI}' < download-job_template.yaml > download-job.yaml

echo "Ensuring ${GCS_FUSE_GSA} can read bucket metadata and write model objects..."
gcloud storage buckets add-iam-policy-binding "gs://${MODEL_BUCKET}" \
  --member="serviceAccount:${GCS_FUSE_GSA}" \
  --role="roles/storage.objectAdmin" >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${MODEL_BUCKET}" \
  --member="serviceAccount:${GCS_FUSE_GSA}" \
  --role="roles/storage.legacyBucketReader" >/dev/null

gcloud container clusters get-credentials gke-europe-west4 --zone europe-west4-a --project="$PROJECT_ID"
gcloud container clusters get-credentials gke-asia-northeast1 --zone asia-northeast1-b --project="$PROJECT_ID"

kubectl config get-contexts "$CTX_EU" >/dev/null
kubectl config get-contexts "$CTX_ASIA" >/dev/null

kubectl apply -f ksa.yaml --context="$CTX_EU"
kubectl apply -f ksa.yaml --context="$CTX_ASIA"
kubectl delete job model-downloader --context="$CTX_ASIA" --ignore-not-found
kubectl wait --for=delete job/model-downloader --context="$CTX_ASIA" --timeout=120s 2>/dev/null || true
kubectl apply -f download-job.yaml --context="$CTX_ASIA"

echo
echo "Model downloader Job created on $CTX_ASIA."
if [[ -n "$SOURCE_MODEL_GCS_URI" ]]; then
  echo "Source mirror: $SOURCE_MODEL_GCS_URI"
else
  echo "Source mirror is not set; the Job will use anonymous Hugging Face download."
fi
echo "Follow logs with:"
echo "kubectl logs -f job/model-downloader --context=\$CTX_ASIA --pod-running-timeout=10m"
