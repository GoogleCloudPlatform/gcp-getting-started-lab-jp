#!/usr/bin/env bash
# deploy.sh — deploy the j5-eks-microservices test bed (fictional equipment marketplace; ems-*) to AWS.
# -----------------------------------------------------------------------------
# Requires kubectl AND docker in addition to terraform + aws cli: this stack is
# dual-layer — Terraform owns the infrastructure, the workloads are Kubernetes
# manifests under k8s/ applied with kubectl (see README.md).
#
# One-shot, idempotent:
#   1. terraform apply       (EKS cluster + nodes, IAM/IRSA, DynamoDB, 2x ECR)
#      ~15-20 min on first run — EKS control plane alone takes ~10 min.
#   2. kubeconfig             dedicated file, no clobbering of ~/.kube/config
#   3. docker build + push    both images (tag = git short sha, or "latest")
#   4. envsubst k8s/ -> k8s-build/, kubectl apply -k, roll + wait for rollout
#   5. wait for the booking-api Service to publish its load-balancer DNS name,
#      then poll /health until the edge answers; print BASE_URL
#
# Required env vars (set them in ~/.aws/journeys.env):
#   EXPECTED_ACCOUNT_ID   abort unless current creds match this account
#   AUTOTEARDOWN_DATE     YYYY-MM-DD for the AutoTeardown tag
# Optional:
#   AWS_REGION            default ap-northeast-1
#   IMAGE_TAG             default: git short sha of this repo, else "latest"
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

for tool in terraform aws docker kubectl envsubst; do
  command -v "$tool" >/dev/null || { echo "FATAL: $tool not found on PATH" >&2; exit 1; }
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got $ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID)" >&2
  exit 1
fi
echo "Deploying j5-eks-microservices to account $ACCOUNT_ID, region $AWS_REGION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
K8S_DIR="${SCRIPT_DIR}/../k8s"
BUILD_DIR="${SCRIPT_DIR}/../k8s-build"
APP_DIR="${SCRIPT_DIR}/../app"

IMAGE_TAG="${IMAGE_TAG:-$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo latest)}"

# ---- 1. terraform apply (infrastructure layer only) ----------------------------
export TF_VAR_autoteardown_date="$AUTOTEARDOWN_DATE"
export TF_VAR_aws_region="$AWS_REGION"

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -input=false -auto-approve

CLUSTER=$(terraform -chdir="$TF_DIR" output -raw cluster_name)
CATALOG_REPO=$(terraform -chdir="$TF_DIR" output -raw ecr_catalog_repository_url)
BOOKING_REPO=$(terraform -chdir="$TF_DIR" output -raw ecr_booking_repository_url)
IRSA_ROLE_ARN=$(terraform -chdir="$TF_DIR" output -raw booking_irsa_role_arn)
ECR_REGISTRY="${CATALOG_REPO%%/*}"

# ---- 2. kubeconfig (dedicated file) ---------------------------------------------
export KUBECONFIG="${HOME}/.kube/config-ems"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER" \
  --kubeconfig "$KUBECONFIG" >/dev/null
echo ">>> kubeconfig written to $KUBECONFIG"

# ---- 3. build + push both images -------------------------------------------------
echo ""
echo ">>> Building and pushing images (tag: ${IMAGE_TAG})"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker build --platform linux/amd64 -t "${CATALOG_REPO}:${IMAGE_TAG}" "${APP_DIR}/catalog-api"
docker push "${CATALOG_REPO}:${IMAGE_TAG}"

docker build --platform linux/amd64 -t "${BOOKING_REPO}:${IMAGE_TAG}" "${APP_DIR}/booking-api"
docker push "${BOOKING_REPO}:${IMAGE_TAG}"

# ---- 4. render manifests + apply the workload layer ------------------------------
# envsubst is restricted to exactly the three placeholders so nothing else in
# the manifests can be mangled.
echo ""
echo ">>> Rendering k8s/ -> k8s-build/ and applying"
export ECR_REGISTRY IMAGE_TAG IRSA_ROLE_ARN
mkdir -p "$BUILD_DIR"
for manifest in "$K8S_DIR"/*.yaml; do
  envsubst '${ECR_REGISTRY} ${IMAGE_TAG} ${IRSA_ROLE_ARN}' \
    < "$manifest" > "${BUILD_DIR}/$(basename "$manifest")"
done

kubectl apply -k "$BUILD_DIR"

# Roll pods so freshly pushed images are picked up even when the tag string
# is unchanged (repeat deploys with IMAGE_TAG=latest).
kubectl -n ems rollout restart deploy/catalog-api deploy/booking-api

kubectl -n ems rollout status deploy/catalog-api --timeout=300s
kubectl -n ems rollout status deploy/booking-api --timeout=300s

# ---- 5. wait for the load balancer ------------------------------------------------
echo ""
echo ">>> Waiting for the booking-api Service to publish a load-balancer hostname"
NLB_HOSTNAME=""
for _ in $(seq 1 60); do # up to 10 min
  NLB_HOSTNAME=$(kubectl -n ems get svc booking-api \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "$NLB_HOSTNAME" ]] && break
  sleep 10
done
if [[ -z "$NLB_HOSTNAME" ]]; then
  echo "FATAL: booking-api Service has no load-balancer hostname after 10 min." >&2
  echo "Inspect with: kubectl -n ems describe svc booking-api" >&2
  exit 1
fi

BASE_URL="http://${NLB_HOSTNAME}"
echo ">>> Load balancer: ${NLB_HOSTNAME}"
echo ">>> Polling ${BASE_URL}/health until the edge answers (target registration"
echo "    and DNS propagation typically take 2-5 min)..."
EDGE_UP=0
for _ in $(seq 1 48); do # up to 8 min
  if curl -sf -m 5 "${BASE_URL}/health" >/dev/null 2>&1; then
    EDGE_UP=1
    break
  fi
  sleep 10
done

echo ""
echo "============================================================"
echo ">>> j5-eks-microservices deployed."
echo "BASE_URL=${BASE_URL}"
if [[ "$EDGE_UP" != "1" ]]; then
  echo ""
  echo "WARNING: the edge did not answer /health within 8 min. New NLBs can"
  echo "take a few extra minutes — retry the smoke test shortly."
fi
echo ""
echo "Next steps:"
echo "  ./scripts/seed.sh ${BASE_URL}"
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo "============================================================"
