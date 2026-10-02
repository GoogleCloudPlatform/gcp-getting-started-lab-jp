#!/usr/bin/env bash
# teardown.sh — destroy every j2-three-tier-web AWS resource.
# -----------------------------------------------------------------------------
# Confirmation-gated: type "yes" at the prompt, or set FORCE_TEARDOWN=1 for
# non-interactive runs.
#
# Deletes the five stacks in strict reverse order with waiters:
#   ttw-observability-stack -> ttw-cdn-stack -> ttw-compute-stack
#   -> ttw-data-stack -> ttw-security-stack
#
# Notes:
#   * The assets bucket is emptied first — CloudFormation cannot delete a
#     non-empty bucket.
#   * The CDN stack is the slow one: CloudFormation disables the CloudFront
#     distribution before deleting it (often 10-20 minutes).
#   * CloudFormation deletes the two Secrets Manager secrets immediately
#     (no recovery window), so redeploys never collide with a
#     scheduled-for-deletion name.
#   * The default VPC and its subnets were only ever referenced as
#     parameters — nothing here touches VPC-level networking.
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
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got $ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID)" >&2
  exit 1
fi

# ---- confirmation gate ---------------------------------------------------------
if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  echo "About to DESTROY all j2-three-tier-web resources in account ${ACCOUNT_ID} (${AWS_REGION})."
  read -r -p 'Type "yes" to continue: ' CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted (nothing destroyed)."
    exit 1
  fi
fi

# ---- helper: delete one stack if it exists ---------------------------------------
delete_stack() {
  local name="$1"
  if aws cloudformation describe-stacks --region "$AWS_REGION" --stack-name "$name" >/dev/null 2>&1; then
    echo ">>> Deleting $name"
    aws cloudformation delete-stack --region "$AWS_REGION" --stack-name "$name"
    aws cloudformation wait stack-delete-complete --region "$AWS_REGION" --stack-name "$name"
    echo "    $name deleted."
  else
    echo ">>> $name not found — skipping."
  fi
}

# ---- pre-empty the assets bucket ---------------------------------------------------
BUCKET="ttw-assets-${ACCOUNT_ID}"
echo ">>> Emptying s3://${BUCKET} (ignore errors if it never existed)"
aws s3 rm "s3://${BUCKET}" --recursive --region "$AWS_REGION" || true

# ---- reverse-order stack deletion ---------------------------------------------------
delete_stack ttw-observability-stack
echo "(ttw-cdn-stack: CloudFront disable+delete typically takes 10-20 minutes)"
delete_stack ttw-cdn-stack
delete_stack ttw-compute-stack
delete_stack ttw-data-stack
delete_stack ttw-security-stack

echo ""
echo "j2-three-tier-web teardown complete."
