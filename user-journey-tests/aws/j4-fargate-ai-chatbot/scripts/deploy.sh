#!/usr/bin/env bash
# deploy.sh — deploy the j4-fargate-ai-chatbot test bed (fictional support desk; fac-*) to AWS.
# -----------------------------------------------------------------------------
# One-shot, idempotent:
#   1. terraform apply          (single apply: ECR, ECS, DynamoDB, S3, IAM, logs)
#   2. docker build + push      (fac-api image into the ECR repo from step 1)
#   3. force-new-deployment     (so the service picks up the freshly pushed tag)
#   4. wait for steady state, resolve the task's public IP, print BASE_URL
#
# On the very first run the ECS service starts before the image exists and its
# tasks fail to pull for a minute or two; step 3 rolls a new deployment after
# the push, so the script still converges. Re-runs are safe (create-or-update).
#
# Required env vars (set them in ~/.aws/journeys.env):
#   EXPECTED_ACCOUNT_ID   abort unless current creds match this account
#   AUTOTEARDOWN_DATE     YYYY-MM-DD for the AutoTeardown tag
# Optional:
#   AWS_REGION            default ap-northeast-1
#   IMAGE_TAG             default latest
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
IMAGE_TAG="${IMAGE_TAG:-latest}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got $ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID)" >&2
  exit 1
fi
echo "Deploying j4-fargate-ai-chatbot to account $ACCOUNT_ID, region $AWS_REGION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"
APP_DIR="${SCRIPT_DIR}/../app"

# ---- LLM mode: stub in this test bed ------------------------------------------
echo ""
echo "============================================================"
echo " NOTE: exporting TF_VAR_llm_mode=stub"
echo " Bedrock model-invocation quotas are ZERO in this lab account,"
echo " so live converse() calls would fail with ThrottlingException."
echo " The stub path keeps /chat, persistence, archiving and all"
echo " smoke-test checks fully exercisable. The Bedrock control-plane"
echo " ping on /admin/aws-check still runs for real."
echo "============================================================"
echo ""
export TF_VAR_llm_mode="stub"

export TF_VAR_autoteardown_date="$AUTOTEARDOWN_DATE"
export TF_VAR_image_tag="$IMAGE_TAG"
export TF_VAR_aws_region="$AWS_REGION"

# ---- 1. terraform apply (single apply) ----------------------------------------
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -input=false -auto-approve

ECR_URL=$(terraform -chdir="$TF_DIR" output -raw ecr_repository_url)
CLUSTER=$(terraform -chdir="$TF_DIR" output -raw cluster_name)
SERVICE=$(terraform -chdir="$TF_DIR" output -raw service_name)
REGISTRY="${ECR_URL%%/*}"

# ---- 2. build + push the fac-api image ----------------------------------------
echo ""
echo ">>> Building and pushing ${ECR_URL}:${IMAGE_TAG}"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"
docker build --platform linux/amd64 -t "${ECR_URL}:${IMAGE_TAG}" "$APP_DIR"
docker push "${ECR_URL}:${IMAGE_TAG}"

# ---- 3. roll the service onto the new image ------------------------------------
echo ""
echo ">>> Forcing new deployment of ${SERVICE}"
aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --force-new-deployment >/dev/null

echo ">>> Waiting for service steady state (can take a few minutes)..."
if ! aws ecs wait services-stable --region "$AWS_REGION" --cluster "$CLUSTER" --services "$SERVICE"; then
  echo "FATAL: service did not stabilize. Inspect with:" >&2
  echo "  aws ecs describe-services --region $AWS_REGION --cluster $CLUSTER --services $SERVICE --query 'services[0].events[:10]'" >&2
  exit 1
fi

# ---- 4. resolve the running task's public IP -----------------------------------
# No load balancer in this stack: clients hit the task IP directly (see
# architecture.md), so the deploy has to dig the IP out of the task's ENI.
TASK_ARN=$(aws ecs list-tasks \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status RUNNING \
  --query 'taskArns[0]' --output text)
if [[ -z "$TASK_ARN" || "$TASK_ARN" == "None" ]]; then
  echo "FATAL: no RUNNING task found for ${SERVICE}" >&2
  exit 1
fi

ENI_ID=$(aws ecs describe-tasks \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER" \
  --tasks "$TASK_ARN" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" \
  --output text)

PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --region "$AWS_REGION" \
  --network-interface-ids "$ENI_ID" \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text)
if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
  echo "FATAL: task ENI $ENI_ID has no public IP association" >&2
  exit 1
fi

BASE_URL="http://${PUBLIC_IP}:8000"
echo ""
echo "============================================================"
echo ">>> j4-fargate-ai-chatbot deployed."
echo "BASE_URL=${BASE_URL}"
echo ""
echo "Next steps:"
echo "  ./scripts/seed.sh ${BASE_URL}"
echo "  ./scripts/smoke-test.sh ${BASE_URL}"
echo ""
echo "The task public IP CHANGES on every deployment — re-run this"
echo "script (or re-resolve the ENI) after any force-new-deployment."
echo "============================================================"
