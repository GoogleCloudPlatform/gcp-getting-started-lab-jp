#!/usr/bin/env bash
# build.sh — assemble the deployable agents-cli project for the copilot.
# -----------------------------------------------------------------------------
# The journey ships a FastAPI service; on Agent Runtime only the AGENT
# migrates (the platform provides serving, the runner, and sessions):
#
#   1. `agents-cli create` scaffolds the supported project shape
#   2. copilot-overlay/ lands the migrated modules: agent.py (model rebound,
#      LiteLLM wrapper deleted), tools.py (one import line), kb.py (creds via
#      the --secrets env injection instead of a boto3 Secrets Manager client)
#   3. the journey's bootstrap.py + corpus are copied VERBATIM — the answer
#      key loads the same 10 documents the AWS estate serves
#   4. pyproject gains psycopg + psycopg-pool (NOT litellm — its deletion is
#      part of the rebinding) and `uv sync` materializes the venv
#
# What has no counterpart here at all: api.py, memory.py, clients.py,
# config.py, Dockerfile — serving, conversation log, AWS SDK funnel, and the
# container itself are all platform concerns now.
# -----------------------------------------------------------------------------

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/deploy/00-env.sh"

command -v agents-cli >/dev/null || {
  echo "FATAL: agents-cli not found (uv tool install google-agents-cli)" >&2
  exit 1
}

JOURNEY="${HERE}/../../../aws/j6-fargate-agentic-rag/app/policyapi"
[[ -f "${JOURNEY}/bootstrap.py" ]] || { echo "FATAL: journey app not found at ${JOURNEY}" >&2; exit 1; }

rm -rf "${STAGE_DIR}"
mkdir -p "$(dirname "${STAGE_DIR}")"

echo ">>> Scaffolding agents-cli project (${PROJECT_NAME})"
(cd "$(dirname "${STAGE_DIR}")" && agents-cli create "${PROJECT_NAME}" \
  -a adk -d agent_runtime -p -y -s --region "${REGION}" -dir policyapi)

echo ">>> Applying copilot-overlay/ + the journey's corpus loader"
cp -r "${HERE}/copilot-overlay/." "${STAGE_DIR}/"
cp "${JOURNEY}/bootstrap.py" "${STAGE_DIR}/policyapi/bootstrap.py"

echo ">>> Adding data-layer dependencies to pyproject.toml"
python3 - "${STAGE_DIR}/pyproject.toml" <<'EOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
anchor = '    "protobuf>=6.31.1,<7.0.0",\n]'
extra = ('    "protobuf>=6.31.1,<7.0.0",\n'
         '    "psycopg[binary]>=3.1,<4.0",\n'
         '    "psycopg-pool>=3.2,<4.0",\n]')
if "psycopg" not in t:
    assert anchor in t, "pyproject anchor moved — template changed, patch by hand"
    p.write_text(t.replace(anchor, extra))
print("deps:", [l.strip() for l in p.read_text().splitlines() if "psycopg" in l])
EOF

echo ">>> uv sync + import check"
(cd "${STAGE_DIR}" && uv sync >/dev/null && uv run python -c "
from policyapi.agent import app, root_agent
assert not any('litellm' in str(type(root_agent.model)).lower() for _ in [0]), 'LiteLLM should be gone'
print('root_agent:', root_agent.name, '| model:', root_agent.model, '| app:', app.name)")

echo ""
echo "Staged at ${STAGE_DIR} — next: ./deploy/04-agent.sh"
