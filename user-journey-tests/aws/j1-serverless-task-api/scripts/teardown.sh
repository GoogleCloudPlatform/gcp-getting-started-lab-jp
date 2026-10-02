#!/usr/bin/env bash
# teardown.sh — destroy the task-reminder stack (bucket contents included).
# Never touches VPCs/subnets (none are created by this journey).
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
: "${AUTOTEARDOWN_DATE:=1970-01-01}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "FATAL: account mismatch (got ${ACCOUNT_ID}, expected ${EXPECTED_ACCOUNT_ID})" >&2
  exit 1
fi

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p "Type 'yes' to destroy j1-serverless-task-api in account ${ACCOUNT_ID}: " answer
  [[ "$answer" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SCRIPT_DIR}/.."

# build dirs must exist for the archive_file data sources during destroy
for fn in tasks_api export_worker cleanup_legacy; do
  mkdir -p "${ROOT}/build/${fn}"
  [[ -f "${ROOT}/build/${fn}/app.py" ]] || cp "${ROOT}/app/functions/${fn}/handler.py" "${ROOT}/build/${fn}/app.py"
  [[ -f "${ROOT}/build/${fn}/aws_clients.py" ]] || cp "${ROOT}/app/shared/aws_clients.py" "${ROOT}/build/${fn}/aws_clients.py"
done

terraform -chdir="${ROOT}/terraform" init -input=false >/dev/null
terraform -chdir="${ROOT}/terraform" destroy -input=false -auto-approve \
  -var "aws_region=${AWS_REGION}" \
  -var "autoteardown_date=${AUTOTEARDOWN_DATE}"

echo "j1-serverless-task-api torn down (exports bucket had force_destroy)."
