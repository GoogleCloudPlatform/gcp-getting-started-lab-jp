#!/usr/bin/env bash
# teardown.sh — destroy the j6-fargate-agentic-rag estate.
# ECR force_delete and RDS skip_final_snapshot are set in the config, so a
# single destroy removes everything including pushed images.

set -euo pipefail

ENV_FILE="${HOME}/.aws/journeys.env"
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
: "${EXPECTED_ACCOUNT_ID:?Set EXPECTED_ACCOUNT_ID in ~/.aws/journeys.env}"
: "${AUTOTEARDOWN_DATE:?Set AUTOTEARDOWN_DATE in ~/.aws/journeys.env}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
[[ "$ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || {
  echo "FATAL: account mismatch (got $ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID)" >&2
  exit 1
}

HERE="$(cd "$(dirname "$0")" && pwd)"
terraform -chdir="${HERE}/../terraform" destroy -input=false -auto-approve \
  -var "autoteardown_date=${AUTOTEARDOWN_DATE}" -var "region=${AWS_REGION}"
echo "j6-fargate-agentic-rag torn down."
