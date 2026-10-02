#!/usr/bin/env bash
# 99-teardown.sh — delete the copilot reference (engines, secret, instance).
# Type "yes", or FORCE_TEARDOWN=1.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/00-env.sh"

if [[ "${FORCE_TEARDOWN:-0}" != "1" ]]; then
  read -r -p "Delete ${PROJECT_NAME} engine(s), ${KB_SECRET} and ${KB_INSTANCE} in ${GCP_PROJECT}? (yes/no) " ANSWER
  [[ "$ANSWER" == "yes" ]] || { echo "aborted"; exit 1; }
fi

TOKEN="$(gcloud auth print-access-token)"
curl -sS -H "Authorization: Bearer ${TOKEN}" "${API_ROOT}/reasoningEngines" | python3 -c "
import json, sys
for e in json.load(sys.stdin).get('reasoningEngines', []):
    if e.get('displayName') == '${PROJECT_NAME}':
        print(e['name'])" | while read -r ENGINE; do
  echo ">>> Deleting ${ENGINE}"
  curl -sS -X DELETE -H "Authorization: Bearer ${TOKEN}" \
    "https://${REGION}-aiplatform.googleapis.com/v1/${ENGINE}?force=true" >/dev/null
done

gcloud secrets delete "${KB_SECRET}" --project "${GCP_PROJECT}" --quiet 2>/dev/null || echo "(secret already absent)"
if gcloud sql instances describe "${KB_INSTANCE}" --project "${GCP_PROJECT}" >/dev/null 2>&1; then
  gcloud sql instances delete "${KB_INSTANCE}" --project "${GCP_PROJECT}" --quiet
else
  echo "(instance already absent)"
fi
rm -f "${HOME}/.config/arc-reference.dbpass"
echo "Teardown complete."
