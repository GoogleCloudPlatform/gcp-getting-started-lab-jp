#!/usr/bin/env bash
# 00-vars.sh — shared variables for the j4-fargate-ai-chatbot GCP reference.
# Source this from every step; it performs no cloud calls.
#
# Override GCP_PROJECT / IMAGE_TAG / MODEL_ID / VERTEX_LOCATION via env.

# The harness GCP project. EVERY gcloud invocation in these scripts passes
# --project "${GCP_PROJECT}" explicitly — the box's default project differs.
export GCP_PROJECT="${GCP_PROJECT:-aws-migration-501814}"
export GCP_REGION="asia-northeast1"

# Vertex endpoint location. The Gemini 2.5 family is served from the global
# endpoint (verified 2026-07), so model calls use "global" while all other
# resources stay in asia-northeast1.
export VERTEX_LOCATION="${VERTEX_LOCATION:-global}"
# Default model (verified 2026-07); overridable without redeploying code.
export MODEL_ID="${MODEL_ID:-gemini-2.5-flash-lite}"

export SERVICE_NAME="fac-api"
export SA_NAME="fac-api-sa"
export SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"

export FIRESTORE_DB="fac-conversations"          # named DB, not (default)
export BUCKET_NAME="fac-transcripts-${GCP_PROJECT}"

export AR_REPO="fac"
export AR_HOST="${GCP_REGION}-docker.pkg.dev"
export IMAGE_TAG="${IMAGE_TAG:-latest}"
export IMAGE_URI="${AR_HOST}/${GCP_PROJECT}/${AR_REPO}/fac-api:${IMAGE_TAG}"
