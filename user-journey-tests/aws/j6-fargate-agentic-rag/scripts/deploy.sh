#!/usr/bin/env bash
# deploy.sh — stand up the j6-fargate-agentic-rag test bed (fictional
# logistics company's policy copilot, arc-*) on AWS.
# -----------------------------------------------------------------------------
# One-shot, idempotent:
#   1. terraform apply     (ALB, ECS, RDS Postgres, DynamoDB, ECR, secret)
#   2. docker build+push   (policy-copilot image into the fresh ECR repo)
#   3. new deployment      (service rolls onto the pushed tag)
#   4. wait steady, print the front URL
#
# First run: the service starts before the image exists and fails to pull for
# a minute; step 3 rolls it after the push, so the run still converges. The
# slow resource is RDS (~5-8 min).
#
# ANSWER_MODE defaults to "pipeline" — the deterministic retrieval loop that
# needs no Bedrock quota. Re-apply with TF_VAR_answer_mode=model to run the
# live google-adk agent over LiteLLM's bedrock/ route (task-role credentials;
# requires Bedrock model access in the account).
#
# Required env (set in ~/.aws/journeys.env):
#   EXPECTED_ACCOUNT_ID   abort unless current creds match
#   AUTOTEARDOWN_DATE     YYYY-MM-DD for the AutoTeardown tag
# Optional: AWS_REGION (default ap-northeast-1), IMAGE_TAG (default latest)
# -----------------------------------------------------------------------------

set -euo pipefail

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
echo "Deploying j6-fargate-agentic-rag to account $ACCOUNT_ID, region $AWS_REGION"

HERE="$(cd "$(dirname "$0")" && pwd)"
TF="${HERE}/../terraform"
APP="${HERE}/../app"

export TF_VAR_autoteardown_date="$AUTOTEARDOWN_DATE"
export TF_VAR_image_tag="$IMAGE_TAG"
export TF_VAR_region="$AWS_REGION"

terraform -chdir="$TF" init -input=false
terraform -chdir="$TF" apply -input=false -auto-approve

REPO=$(terraform -chdir="$TF" output -raw image_repo)
CLUSTER=$(terraform -chdir="$TF" output -raw cluster)
SERVICE=$(terraform -chdir="$TF" output -raw service)
FRONT=$(terraform -chdir="$TF" output -raw front_url)

echo ""
echo ">>> Building and pushing ${REPO}:${IMAGE_TAG}"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build --platform linux/amd64 -t "${REPO}:${IMAGE_TAG}" "$APP"
docker push "${REPO}:${IMAGE_TAG}"

echo ""
echo ">>> Rolling ${SERVICE} onto the pushed image"
aws ecs update-service --region "$AWS_REGION" --cluster "$CLUSTER" \
  --service "$SERVICE" --force-new-deployment >/dev/null

echo ">>> Waiting for steady state..."
aws ecs wait services-stable --region "$AWS_REGION" --cluster "$CLUSTER" --services "$SERVICE"

echo ""
echo "============================================================"
echo ">>> j6-fargate-agentic-rag deployed."
echo "BASE_URL=${FRONT}"
echo ""
echo "Next:"
echo "  ./scripts/bootstrap-kb.sh          # schema + policy corpus"
echo "  ./scripts/smoke-test.sh ${FRONT}"
echo "============================================================"
