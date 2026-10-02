#!/usr/bin/env bash
# 00-env.sh — shared variables for the copilot's Agent Runtime reference.
# No cloud calls except the memoized project-number lookup.

export GCP_PROJECT="${GCP_PROJECT:-aws-migration-501814}"
export REGION="${REGION:-asia-northeast1}"

export PROJECT_NAME="policy-copilot"
export STAGE_DIR="${STAGE_DIR:-/tmp/arc-reference/${PROJECT_NAME}}"

# Cloud SQL knowledge base (the RDS counterpart; FTS schema lifts unchanged)
export KB_INSTANCE="arc-kb"
export KB_DATABASE="policykb"
export KB_USER="copilot"

# Secret Manager secret whose VALUE agents-cli --secrets injects as the
# KB_CONNECTION_JSON env var on the engine
export KB_SECRET="arc-kb-connection"

PROJECT_NUMBER="$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')"
export PROJECT_NUMBER
# Agent Runtime executes as the AI Platform Reasoning Engine service agent.
export RUNTIME_SA="service-${PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"

export API_ROOT="https://${REGION}-aiplatform.googleapis.com/v1/projects/${GCP_PROJECT}/locations/${REGION}"

# Newest engine whose display name matches the project (agents-cli names the
# deployment after the project directory). Prints nothing when none exists.
copilot_engine() {
  curl -sS -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "${API_ROOT}/reasoningEngines" | python3 -c "
import json, sys
engines = [e for e in json.load(sys.stdin).get('reasoningEngines', [])
           if e.get('displayName') == '${PROJECT_NAME}']
engines.sort(key=lambda e: e.get('createTime', ''), reverse=True)
print(engines[0]['name'] if engines else '')"
}
