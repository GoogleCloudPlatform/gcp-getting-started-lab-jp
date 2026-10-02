#!/usr/bin/env bash
# bootstrap-kb.sh — load the knowledge-base schema and corpus (idempotent).
# -----------------------------------------------------------------------------
# The Postgres instance admits only the workload security group, so this runs
# `python -m policyapi.bootstrap` as a one-off Fargate task inside the same
# subnets/SG/role envelope as the service, waits for it to stop, and prints
# its log tail. Re-runs reload the corpus to exactly the file's contents.
# -----------------------------------------------------------------------------

set -euo pipefail

ENV_FILE="${HOME}/.aws/journeys.env"
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
: "${EXPECTED_ACCOUNT_ID:?Set EXPECTED_ACCOUNT_ID in ~/.aws/journeys.env}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
[[ "$ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || {
  echo "FATAL: account mismatch (got $ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID)" >&2
  exit 1
}

HERE="$(cd "$(dirname "$0")" && pwd)"
TF="${HERE}/../terraform"

CLUSTER=$(terraform -chdir="$TF" output -raw cluster)
FAMILY=$(terraform -chdir="$TF" output -raw task_family)
SG=$(terraform -chdir="$TF" output -raw workload_security_group)
SUBNETS=$(terraform -chdir="$TF" output -json subnets | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)))')

echo ">>> Launching one-off bootstrap task (${FAMILY})"
TASK=$(aws ecs run-task --region "$AWS_REGION" --cluster "$CLUSTER" \
  --launch-type FARGATE --task-definition "$FAMILY" \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SG}],assignPublicIp=ENABLED}" \
  --overrides '{"containerOverrides":[{"name":"copilot","command":["python","-m","policyapi.bootstrap"]}]}' \
  --query 'tasks[0].taskArn' --output text)
echo "    ${TASK}"

aws ecs wait tasks-stopped --region "$AWS_REGION" --cluster "$CLUSTER" --tasks "$TASK"
EXIT=$(aws ecs describe-tasks --region "$AWS_REGION" --cluster "$CLUSTER" --tasks "$TASK" \
  --query 'tasks[0].containers[0].exitCode' --output text)

STREAM="copilot/copilot/${TASK##*/}"
echo ">>> Log tail (${STREAM}):"
aws logs get-log-events --region "$AWS_REGION" --log-group-name /arc/policy-copilot \
  --log-stream-name "$STREAM" --limit 10 --query 'events[].message' --output text 2>/dev/null \
  || echo "(no log events)"

[[ "$EXIT" == "0" ]] || { echo "FATAL: bootstrap task exit code ${EXIT}" >&2; exit 1; }
echo "Knowledge base loaded."
