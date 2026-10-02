#!/usr/bin/env bash
# 07-wait-lb.sh — wait for the booking-api LoadBalancer external IP and print
# the BASE_URL for the journey's smoke test.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
export KUBECONFIG="${HOME}/.kube/config-ems-gcp"

for _ in $(seq 1 60); do
  IP=$(kubectl -n "${K8S_NAMESPACE}" get svc booking-api \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${IP:-}" ]]; then
    echo ""
    echo "BASE_URL=http://${IP}"
    echo "Parity: ../../../../user-journey-tests/aws/j5-eks-microservices/scripts/smoke-test.sh http://${IP}"
    exit 0
  fi
  echo "waiting for LoadBalancer IP…"
  sleep 10
done
echo "FATAL: LoadBalancer IP not assigned within 10 min" >&2
exit 1
