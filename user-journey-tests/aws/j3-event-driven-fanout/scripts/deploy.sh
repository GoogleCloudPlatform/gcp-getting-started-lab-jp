#!/usr/bin/env bash
# deploy.sh — bundle the functions and deploy the SAM template WITHOUT the
# sam CLI: `aws cloudformation package` uploads CodeUri dirs, `deploy`
# expands the Serverless transform (CAPABILITY_AUTO_EXPAND).
# Idempotent: package+deploy are create-or-update.
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

STACK_NAME="edf-pipeline-stack"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Deploying j3-event-driven-fanout to account ${ACCOUNT_ID}, region ${AWS_REGION}"
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got ${ACCOUNT_ID}, expected ${EXPECTED_ACCOUNT_ID})" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
BUILD="${ROOT}/build"

# ---- assemble per-function bundles (index + funnel + prod deps) ---------------
echo ">>> bundling functions"
(cd "${ROOT}/app" && npm install --omit=dev --no-audit --no-fund >/dev/null)
for fn in worker digest; do
  rm -rf "${BUILD}/${fn}"
  mkdir -p "${BUILD}/${fn}"
  cp "${ROOT}/app/${fn}/index.mjs" "${BUILD}/${fn}/index.mjs"
  cp "${ROOT}/app/shared/awsClients.mjs" "${BUILD}/${fn}/awsClients.mjs"
  cp "${ROOT}/app/package.json" "${BUILD}/${fn}/package.json"
  cp -r "${ROOT}/app/node_modules" "${BUILD}/${fn}/node_modules"
done

# ---- package (uploads bundles to the artifacts bucket) -------------------------
ARTIFACTS_BUCKET="edf-artifacts-${ACCOUNT_ID}"
if ! aws s3api head-bucket --bucket "$ARTIFACTS_BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$ARTIFACTS_BUCKET" --region "$AWS_REGION" \
    --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
fi

aws cloudformation package \
  --region "$AWS_REGION" \
  --template-file "${ROOT}/sam/template.yaml" \
  --s3-bucket "$ARTIFACTS_BUCKET" \
  --s3-prefix lambda-bundles \
  --output-template-file "${BUILD}/packaged.yaml" >/dev/null
echo ">>> packaged to build/packaged.yaml"

aws cloudformation deploy \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "${BUILD}/packaged.yaml" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides "AutoTeardownDate=${AUTOTEARDOWN_DATE}" \
  --no-fail-on-empty-changeset

echo ""
echo "Deploy complete. Stack: ${STACK_NAME}"
aws cloudformation describe-stacks --region "$AWS_REGION" --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table
echo "Next: ./scripts/seed.sh && ./scripts/smoke-test.sh aws"
