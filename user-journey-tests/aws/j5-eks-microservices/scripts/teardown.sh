#!/usr/bin/env bash
# teardown.sh — destroy every j5-eks-microservices AWS resource.
# -----------------------------------------------------------------------------
# Confirmation-gated: type "yes" at the prompt, or set FORCE_TEARDOWN=1 for
# non-interactive runs.
#
# Order matters in a dual-layer stack: the NLB was provisioned by the CLUSTER
# from the booking-api Service object, so Terraform knows nothing about it.
# Destroying the cluster first would orphan the NLB (it would keep billing
# forever). Therefore:
#   1. kubectl delete svc booking-api   -> cloud controller deletes the NLB
#   2. poll elbv2 until that NLB's DNS name is really gone (up to 5 min)
#   3. delete the remaining workload objects / namespace
#   4. terraform destroy                -> nodes, cluster, IAM, table, ECR
#
# The default VPC and its subnets are DATA SOURCES — never touched.
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- load env + pre-flight account guard -------------------------------------
ENV_FILE="${HOME}/.aws/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_ACCOUNT_ID, AUTOTEARDOWN_DATE)" >&2
  exit 1
fi
: "${EXPECTED_ACCOUNT_ID:?Set EXPECTED_ACCOUNT_ID in ~/.aws/journeys.env}"
: "${AUTOTEARDOWN_DATE:?Set AUTOTEARDOWN_DATE=YYYY-MM-DD in ~/.aws/journeys.env}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got $ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID)" >&2
  exit 1
fi

# ---- confirmation gate ---------------------------------------------------------
if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  echo "About to DESTROY all j5-eks-microservices resources in account ${ACCOUNT_ID} (${AWS_REGION})."
  read -r -p 'Type "yes" to continue: ' CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted (nothing destroyed)."
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
BUILD_DIR="${SCRIPT_DIR}/../k8s-build"
CLUSTER="ems-cluster"

export TF_VAR_autoteardown_date="$AUTOTEARDOWN_DATE"
export TF_VAR_aws_region="$AWS_REGION"

# ---- 1-3. workload layer first (only if the cluster still exists) ---------------
if aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER" >/dev/null 2>&1; then
  export KUBECONFIG="${HOME}/.kube/config-ems"
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER" \
    --kubeconfig "$KUBECONFIG" >/dev/null

  NLB_HOSTNAME=$(kubectl -n ems get svc booking-api \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

  echo ">>> Deleting the booking-api Service (releases the NLB)..."
  kubectl -n ems delete svc booking-api --ignore-not-found --timeout=120s || true

  if [[ -n "${NLB_HOSTNAME:-}" ]]; then
    echo ">>> Waiting for NLB ${NLB_HOSTNAME} to disappear (up to 5 min)..."
    NLB_GONE=0
    for _ in $(seq 1 30); do
      if ! aws elbv2 describe-load-balancers --region "$AWS_REGION" \
        --query 'LoadBalancers[].DNSName' --output text 2>/dev/null \
        | tr '\t' '\n' | grep -qx "$NLB_HOSTNAME"; then
        NLB_GONE=1
        break
      fi
      sleep 10
    done
    if [[ "$NLB_GONE" == "1" ]]; then
      echo ">>> NLB is gone."
    else
      echo "WARNING: NLB ${NLB_HOSTNAME} still listed after 5 min; continuing." >&2
      echo "         Re-check later: aws elbv2 describe-load-balancers --region $AWS_REGION" >&2
    fi
  fi

  echo ">>> Deleting the remaining workload objects..."
  if [[ -d "$BUILD_DIR" ]]; then
    kubectl delete -k "$BUILD_DIR" --ignore-not-found --timeout=180s || true
  fi
  kubectl delete namespace ems --ignore-not-found --timeout=180s || true
else
  echo ">>> Cluster ${CLUSTER} not found — skipping the workload layer."
fi

# ---- 4. infrastructure layer ------------------------------------------------------
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" destroy -input=false -auto-approve

rm -f "${HOME}/.kube/config-ems"

echo ""
echo "j5-eks-microservices teardown complete."
