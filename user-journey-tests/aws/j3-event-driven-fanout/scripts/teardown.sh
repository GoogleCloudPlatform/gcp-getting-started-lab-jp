#!/usr/bin/env bash
# teardown.sh — empty the buckets and delete the pipeline stack.
# No VPC involvement anywhere in this journey.
set -euo pipefail

ENV_FILE="${HOME}/.aws/journeys.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "FATAL: $ENV_FILE not found (needs EXPECTED_ACCOUNT_ID)" >&2
  exit 1
fi
: "${EXPECTED_ACCOUNT_ID:?Set EXPECTED_ACCOUNT_ID in ~/.aws/journeys.env}"
: "${AWS_REGION:=ap-northeast-1}"

STACK_NAME="edf-pipeline-stack"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got ${ACCOUNT_ID}, expected ${EXPECTED_ACCOUNT_ID})" >&2
  exit 1
fi

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p "Type 'yes' to destroy j3-event-driven-fanout in account ${ACCOUNT_ID}: " answer
  [[ "$answer" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

for bucket in "edf-uploads-${ACCOUNT_ID}" "edf-artifacts-${ACCOUNT_ID}"; do
  if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    echo ">>> emptying s3://${bucket}"
    aws s3 rm "s3://${bucket}" --recursive || true
  fi
done

echo ">>> deleting stack ${STACK_NAME}"
aws cloudformation delete-stack --region "$AWS_REGION" --stack-name "$STACK_NAME"
aws cloudformation wait stack-delete-complete --region "$AWS_REGION" --stack-name "$STACK_NAME"

# artifacts bucket is not part of the stack
aws s3api delete-bucket --bucket "edf-artifacts-${ACCOUNT_ID}" --region "$AWS_REGION" 2>/dev/null || true
echo "j3-event-driven-fanout torn down."
