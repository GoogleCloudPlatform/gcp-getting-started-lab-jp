#!/usr/bin/env bash
# 04-agent.sh — deploy the staged copilot to Agent Runtime.
#
# The command the migration skill's runbook centers on. Two things to notice:
#   --secrets maps the Secret Manager secret's VALUE into the engine's
#     KB_CONNECTION_JSON env var (the code has no secrets client), and the
#     list carries NO AWS credentials — the Bedrock binding was rebound, not
#     smuggled along.
#   A re-run creates a NEW engine while the previous one keeps serving until
#     deleted; 99-teardown.sh removes every engine with this display name.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/00-env.sh"

[[ -d "${STAGE_DIR}" ]] || { echo "FATAL: run ../build.sh first" >&2; exit 1; }

# Deploy AFTER 02: the platform checks secret ACCESS at deploy time, and the
# serving instance freezes its env at start — a placeholder secret here means
# a copilot that times out on every tool call until the instance recycles.
KB_HOST_IN_SECRET="$(gcloud secrets versions access latest --secret="${KB_SECRET}" \
  --project "${GCP_PROJECT}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("host",""))' || true)"
[[ -n "${KB_HOST_IN_SECRET}" ]] || { echo "FATAL: ${KB_SECRET} has no host yet — run ./02-knowledge-base.sh first" >&2; exit 1; }

(cd "${STAGE_DIR}" && agents-cli deploy \
  --deployment-target agent_runtime \
  --project "${GCP_PROJECT}" \
  --region "${REGION}" \
  --min-instances 0 \
  --secrets "KB_CONNECTION_JSON=${KB_SECRET}" \
  --no-confirm-project)

echo ""
echo "Deployed: $(copilot_engine)"
echo "Next: ./05-verify.sh"
