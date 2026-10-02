#!/usr/bin/env bash
# deploy.sh — deploy the j2-three-tier-web test bed (the online shop, ttw-*) to AWS.
# -----------------------------------------------------------------------------
# Idempotent: every stack goes through `aws cloudformation deploy`
# (create-or-update) with --no-fail-on-empty-changeset, and the bundle upload
# just overwrites. Order:
#
#   1. ttw-security-stack       security groups + both secrets
#   2. ttw-data-stack           RDS PostgreSQL (~10-15 min first time) + assets bucket
#   3. bundle upload            app/app.tar.gz + covers/*.png into the bucket
#   4. ttw-compute-stack        ALB + launch template + ASG (instances pull the bundle)
#   5. ttw-cdn-stack            CloudFront in front of the ALB
#   6. ttw-observability-stack  log group + the two console alarms
#
# STACK NAMES ARE LOAD-BEARING: templates ImportValue each other by the fixed
# names ttw-security-stack / ttw-data-stack / ttw-compute-stack — do not rename.
#
# The default VPC and its subnets are RESOLVED here and passed as parameters;
# nothing in this journey ever creates or deletes VPC-level networking.
#
# Required env vars (set them in ~/.aws/journeys.env):
#   EXPECTED_ACCOUNT_ID   abort unless current creds match this account
#   AUTOTEARDOWN_DATE     YYYY-MM-DD for the AutoTeardown tag
# Optional:
#   AWS_REGION            default ap-northeast-1
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
echo "Deploying j2-three-tier-web to account $ACCOUNT_ID, region $AWS_REGION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CFN_DIR="${SCRIPT_DIR}/../cloudformation"
APP_DIR="${SCRIPT_DIR}/../app"

# ---- resolve the default VPC + its subnets ------------------------------------
VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "FATAL: no default VPC in $AWS_REGION (this journey only uses the default VPC)" >&2
  exit 1
fi

SUBNET_IDS=$(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=${VPC_ID}" Name=default-for-az,Values=true \
  --query 'Subnets[].SubnetId' --output text | tr '[:space:]' ',' | sed 's/,*$//')
SUBNET_COUNT=$(awk -F',' '{print NF}' <<<"$SUBNET_IDS")
if [[ "$SUBNET_COUNT" -lt 2 ]]; then
  echo "FATAL: need >=2 default subnets for the ALB/RDS, found: '$SUBNET_IDS'" >&2
  exit 1
fi
echo "Default VPC: $VPC_ID  subnets: $SUBNET_IDS"

# ---- helper: deploy one stack ---------------------------------------------------
deploy() {
  local stack_name="$1" template="$2"; shift 2
  echo ""
  echo ">>> Deploying $stack_name from $template"
  aws cloudformation deploy \
    --region "$AWS_REGION" \
    --stack-name "$stack_name" \
    --template-file "${CFN_DIR}/${template}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides "AutoTeardownDate=${AUTOTEARDOWN_DATE}" "$@" \
    --no-fail-on-empty-changeset
}

# ---- 1-2. security + data -------------------------------------------------------
deploy ttw-security-stack security/security-groups-secrets.yaml "VpcId=${VPC_ID}"

echo "(ttw-data-stack creates the RDS instance — first run takes ~10-15 minutes)"
deploy ttw-data-stack data/database-storage.yaml "SubnetIds=${SUBNET_IDS}"

# ---- 3. bundle + covers into the assets bucket -----------------------------------
BUCKET="ttw-assets-${ACCOUNT_ID}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo ""
echo ">>> Uploading app bundle + covers to s3://${BUCKET}"
tar czf "${WORK_DIR}/app.tar.gz" --exclude='__pycache__' --exclude='*.pyc' -C "$APP_DIR" .
python3 "${SCRIPT_DIR}/make-covers.py" "${WORK_DIR}/covers"
aws s3 cp "${WORK_DIR}/app.tar.gz" "s3://${BUCKET}/app/app.tar.gz" --region "$AWS_REGION"
aws s3 sync "${WORK_DIR}/covers" "s3://${BUCKET}/covers/" --region "$AWS_REGION"

# ---- 4-6. compute + cdn + observability -------------------------------------------
deploy ttw-compute-stack compute/alb-asg.yaml "VpcId=${VPC_ID}" "SubnetIds=${SUBNET_IDS}"
deploy ttw-cdn-stack cdn/cloudfront.yaml
deploy ttw-observability-stack observability/alarms.yaml

# ---- outputs -----------------------------------------------------------------------
ALB_DNS=$(aws cloudformation describe-stacks --region "$AWS_REGION" \
  --stack-name ttw-compute-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`AlbDnsName`].OutputValue' --output text)
CDN_DOMAIN=$(aws cloudformation describe-stacks --region "$AWS_REGION" \
  --stack-name ttw-cdn-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`DistributionDomainName`].OutputValue' --output text)

echo ""
echo "============================================================"
echo ">>> j2-three-tier-web deployed."
echo "BASE_URL=http://${ALB_DNS}"
echo "CDN_URL=https://${CDN_DOMAIN}"
echo ""
echo "Instances self-seed the catalog at boot (schema + 12 books);"
echo "allow a few minutes after first deploy for the ASG to bootstrap"
echo "and pass ALB health checks, then:"
echo "  ./scripts/smoke-test.sh http://${ALB_DNS}"
echo "  ./scripts/smoke-test.sh https://${CDN_DOMAIN}   # via CloudFront"
echo "============================================================"
