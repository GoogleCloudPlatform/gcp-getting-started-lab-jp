#!/usr/bin/env bash
# teardown.sh — destroy every j4-fargate-ai-chatbot AWS resource.
# -----------------------------------------------------------------------------
# Confirmation-gated: type "yes" at the prompt, or set FORCE_TEARDOWN=1 for
# non-interactive runs.
#
# `terraform destroy` walks the dependency graph in reverse creation order
# (service -> task def -> cluster/logs/SG -> table/bucket/repo -> IAM).
# The S3 bucket (force_destroy) and ECR repo (force_delete) are removed even
# when they still hold objects/images. The VPC and subnets are DATA SOURCES —
# this stack never creates or deletes them.
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
  echo "About to DESTROY all j4-fargate-ai-chatbot resources in account ${ACCOUNT_ID} (${AWS_REGION})."
  read -r -p 'Type "yes" to continue: ' CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted (nothing destroyed)."
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

export TF_VAR_autoteardown_date="$AUTOTEARDOWN_DATE"
export TF_VAR_aws_region="$AWS_REGION"

terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" destroy -input=false -auto-approve

echo ""
echo "j4-fargate-ai-chatbot teardown complete."
