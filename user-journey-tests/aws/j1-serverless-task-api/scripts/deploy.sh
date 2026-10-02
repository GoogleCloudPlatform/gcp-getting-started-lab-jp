#!/usr/bin/env bash
# deploy.sh — build Lambda bundles and terraform-apply the task-reminder stack.
# Idempotent: re-runs are safe (terraform apply is convergent).
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
: "${AUTOTEARDOWN_DATE:?Set AUTOTEARDOWN_DATE=YYYY-MM-DD (resource tag)}"
: "${AWS_REGION:=ap-northeast-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Deploying j1-serverless-task-api to account ${ACCOUNT_ID}, region ${AWS_REGION}"
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got ${ACCOUNT_ID}, expected ${EXPECTED_ACCOUNT_ID})" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
BUILD="${ROOT}/build"

# ---- assemble per-function build dirs (handler.py -> app.py + shared funnel)
for fn in tasks_api export_worker cleanup_legacy; do
  mkdir -p "${BUILD}/${fn}"
  cp "${ROOT}/app/functions/${fn}/handler.py" "${BUILD}/${fn}/app.py"
  cp "${ROOT}/app/shared/aws_clients.py" "${BUILD}/${fn}/aws_clients.py"
done
echo "Lambda bundles assembled under build/"

# ---- terraform
terraform -chdir="${ROOT}/terraform" init -input=false -upgrade=false >/dev/null
terraform -chdir="${ROOT}/terraform" apply -input=false -auto-approve \
  -var "aws_region=${AWS_REGION}" \
  -var "autoteardown_date=${AUTOTEARDOWN_DATE}"

API_ENDPOINT=$(terraform -chdir="${ROOT}/terraform" output -raw api_endpoint)
echo ""
echo "Deploy complete."
echo "BASE_URL=${API_ENDPOINT}"
echo "Next: ./scripts/seed.sh && ./scripts/smoke-test.sh ${API_ENDPOINT}"
