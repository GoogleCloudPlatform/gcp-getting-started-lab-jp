#!/usr/bin/env bash
# 00-vars.sh — shared variables for the j2-three-tier-web GCP reference.
# Source this from every step; it performs no cloud calls.
#
# The harness GCP project. EVERY gcloud invocation in these scripts passes
# --project "${GCP_PROJECT}" explicitly — the box's default project differs.

export GCP_PROJECT="${GCP_PROJECT:-aws-migration-501814}"
export GCP_REGION="asia-northeast1"
export GCP_ZONE="${GCP_ZONE:-asia-northeast1-b}"

export SA_NAME="ttw-app-sa"
export SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"

export BUCKET_NAME="ttw-assets-${GCP_PROJECT}"

export SQL_INSTANCE="ttw-postgres"
export SQL_CONNECTION="${GCP_PROJECT}:${GCP_REGION}:${SQL_INSTANCE}"
export DB_NAME="online_shop"
export DB_USER="shop"

export SECRET_DB="ttw-db-password"
export SECRET_LEGACY="ttw-legacy-api-key"

export TEMPLATE_NAME="ttw-app-tmpl"
export MIG_NAME="ttw-mig"
export MIG_SIZE=2

export HC_NAME="ttw-hc"
export BACKEND_NAME="ttw-backend"
export URLMAP_NAME="ttw-url-map"
export PROXY_NAME="ttw-http-proxy"
export FWD_RULE="ttw-fwd"
export LB_IP_NAME="ttw-lb-ip"

export FW_HEALTH="ttw-allow-health"
export FW_LB="ttw-allow-lb"

# Cloud SQL Auth Proxy v2 — pinned; binary URL pattern
# https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.*/cloud-sql-proxy.linux.amd64
# (verified 2026-07). Bump deliberately, then roll the MIG.
export SQL_PROXY_VERSION="v2.14.2"
