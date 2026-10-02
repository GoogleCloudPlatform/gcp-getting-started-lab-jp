#!/usr/bin/env bash
# 07-firewall.sh — ingress to the app VMs (default network, tag ttw-app).
#
# The AWS ttw-app-sg allowed :8000 from the ALB security group. The GCP
# global external Application LB is proxy-based: both its health checks AND
# its data plane originate from Google's published ranges 130.211.0.0/22 and
# 35.191.0.0/16, so nothing else ever needs to reach :8000 directly.
# Two rules (health / lb) keep the two concerns readable even though the
# ranges coincide.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00-vars.sh"

ensure_rule() {
  local name="$1" desc="$2"
  if ! gcloud compute firewall-rules describe "$name" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
    gcloud compute firewall-rules create "$name" \
      --project "${GCP_PROJECT}" \
      --network=default \
      --direction=INGRESS \
      --action=ALLOW \
      --rules=tcp:8000 \
      --source-ranges=130.211.0.0/22,35.191.0.0/16 \
      --target-tags=ttw-app \
      --description="$desc"
  else
    echo "Firewall rule $name already exists."
  fi
}

ensure_rule "${FW_HEALTH}" "Online shop: LB health checks -> gunicorn :8000 (ttw-app-tg health check analogue)"
ensure_rule "${FW_LB}" "Online shop: global external ALB data plane -> gunicorn :8000 (ttw-alb-sg -> ttw-app-sg analogue)"

echo "Firewall rules ready."
