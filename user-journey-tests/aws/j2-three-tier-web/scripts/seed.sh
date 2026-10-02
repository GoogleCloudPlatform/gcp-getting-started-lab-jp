#!/usr/bin/env bash
# seed.sh — refresh the online shop seed material (bundle + covers).
# -----------------------------------------------------------------------------
# The catalog rows themselves are self-seeded by the app at boot
# (db.bootstrap(): schema + 12 deterministic books, ON CONFLICT DO NOTHING),
# so there is no SQL to run here. What this script does:
#
#   1. Rebuild and re-upload app/app.tar.gz and covers/*.png to the assets
#      bucket (same artifacts deploy.sh uploads).
#   2. Optionally roll the ASG onto the new bundle:
#        ./scripts/seed.sh --refresh      (or REFRESH_INSTANCES=1)
#      Instances only read the bundle at boot, so without a refresh the
#      running fleet keeps serving the old code.
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

REFRESH="${REFRESH_INSTANCES:-0}"
if [[ "${1:-}" == "--refresh" ]]; then
  REFRESH=1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/../app"
BUCKET="ttw-assets-${ACCOUNT_ID}"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo ">>> Re-uploading bundle + covers to s3://${BUCKET}"
tar czf "${WORK_DIR}/app.tar.gz" --exclude='__pycache__' --exclude='*.pyc' -C "$APP_DIR" .
python3 "${SCRIPT_DIR}/make-covers.py" "${WORK_DIR}/covers"
aws s3 cp "${WORK_DIR}/app.tar.gz" "s3://${BUCKET}/app/app.tar.gz" --region "$AWS_REGION"
aws s3 sync "${WORK_DIR}/covers" "s3://${BUCKET}/covers/" --region "$AWS_REGION"

if [[ "$REFRESH" == "1" ]]; then
  echo ">>> Starting instance refresh on ttw-asg (instances re-pull the bundle at boot)"
  aws autoscaling start-instance-refresh \
    --region "$AWS_REGION" \
    --auto-scaling-group-name ttw-asg \
    --preferences MinHealthyPercentage=50 >/dev/null
  echo "Refresh started; watch with:"
  echo "  aws autoscaling describe-instance-refreshes --region $AWS_REGION --auto-scaling-group-name ttw-asg"
else
  echo "(fleet not refreshed — run with --refresh to roll instances onto the new bundle)"
fi

echo "Done."
