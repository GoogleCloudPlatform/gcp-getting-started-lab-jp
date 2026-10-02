#!/usr/bin/env bash
# 09-lb.sh — global external Application Load Balancer with Cloud CDN
# (the ALB + CloudFront analogue), HTTP :80 on a reserved global IP:
#
#   forwarding rule ttw-fwd :80 -> proxy ttw-http-proxy -> url-map ttw-url-map
#     -> backend service ttw-backend (Cloud CDN on, CACHE_ALL_STATIC)
#       -> MIG ttw-mig via named port http:8000, health check ttw-hc /health
#
# CDN parity note: CloudFront cached exactly /static/* (managed
# CachingOptimized) and bypassed everything else (CachingDisabled).
# CACHE_ALL_STATIC reproduces that split by content type: the css under
# /static/ is cacheable static content, while the HTML pages and JSON
# endpoints are not cached (and, like the AWS side, /covers/*.png images
# also become cacheable — the 2021 contractor would approve).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

# ---- reserved global IP (stable BASE_URL across re-runs) -----------------------
if ! gcloud compute addresses describe "${LB_IP_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute addresses create "${LB_IP_NAME}" --global --project "${GCP_PROJECT}"
else
  echo "Address ${LB_IP_NAME} already exists."
fi

# ---- health check ----------------------------------------------------------------
if ! gcloud compute health-checks describe "${HC_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute health-checks create http "${HC_NAME}" \
    --project "${GCP_PROJECT}" \
    --global \
    --port=8000 \
    --request-path=/health \
    --check-interval=15s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=5
else
  echo "Health check ${HC_NAME} already exists."
fi

# ---- backend service + Cloud CDN ----------------------------------------------------
if ! gcloud compute backend-services describe "${BACKEND_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute backend-services create "${BACKEND_NAME}" \
    --project "${GCP_PROJECT}" \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTP \
    --port-name=http \
    --health-checks="${HC_NAME}" \
    --timeout=30s \
    --enable-cdn \
    --cache-mode=CACHE_ALL_STATIC
else
  echo "Backend service ${BACKEND_NAME} already exists."
fi

if ! gcloud compute backend-services describe "${BACKEND_NAME}" --global --project "${GCP_PROJECT}" \
     --format='value(backends[].group)' | grep -q "${MIG_NAME}"; then
  gcloud compute backend-services add-backend "${BACKEND_NAME}" \
    --project "${GCP_PROJECT}" \
    --global \
    --instance-group="${MIG_NAME}" \
    --instance-group-zone="${GCP_ZONE}"
else
  echo "Backend ${MIG_NAME} already attached."
fi

# ---- url map / proxy / forwarding rule -------------------------------------------------
if ! gcloud compute url-maps describe "${URLMAP_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute url-maps create "${URLMAP_NAME}" \
    --project "${GCP_PROJECT}" \
    --global \
    --default-service "${BACKEND_NAME}"
else
  echo "URL map ${URLMAP_NAME} already exists."
fi

if ! gcloud compute target-http-proxies describe "${PROXY_NAME}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute target-http-proxies create "${PROXY_NAME}" \
    --project "${GCP_PROJECT}" \
    --global \
    --url-map "${URLMAP_NAME}"
else
  echo "Target proxy ${PROXY_NAME} already exists."
fi

if ! gcloud compute forwarding-rules describe "${FWD_RULE}" --global --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud compute forwarding-rules create "${FWD_RULE}" \
    --project "${GCP_PROJECT}" \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --address="${LB_IP_NAME}" \
    --target-http-proxy="${PROXY_NAME}" \
    --ports=80
else
  echo "Forwarding rule ${FWD_RULE} already exists."
fi

LB_IP="$(gcloud compute addresses describe "${LB_IP_NAME}" --global --project "${GCP_PROJECT}" --format='value(address)')"

echo ""
echo "============================================================"
echo ">>> j2-three-tier-web GCP reference deployed."
echo "BASE_URL=http://${LB_IP}"
echo ""
echo "New global LBs take a few minutes to start serving. Then run the"
echo "JOURNEY's smoke test, unmodified:"
echo "  ../../../../user-journey-tests/aws/j2-three-tier-web/scripts/smoke-test.sh http://${LB_IP}"
echo "============================================================"
