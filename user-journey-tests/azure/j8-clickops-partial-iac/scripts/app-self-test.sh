#!/usr/bin/env bash
# app-self-test.sh — start the portal the way App Service starts it, and assert
# it comes up.
# -----------------------------------------------------------------------------
# This is a laptop test. It talks to no Azure subscription and needs no
# credentials.
#
# It exists because a portal that imports cleanly in a checkout can still fail to
# start on the platform, and the difference is never the code — it is the shape
# around the code. So nothing here is retyped from the template:
#
#   * the archive is built by scripts/package-app.py, the same packager
#     scripts/deploy.sh pushes with, and the test runs from the UNPACKED archive.
#     What is tested is the directory the platform gets, not the working tree.
#   * the command line comes out of bicep/modules/webapp.bicep. Only the bind
#     address is rewritten, so a startup command edited in the template without
#     the app following it fails here rather than in a deployment.
#
# Postures:
#   1 bare          nothing configured — a worker whose settings have not
#                   arrived yet, which is the state a cold instance starts in
#   2 unreachable   both connection strings present and pointing at endpoints
#                   that do not resolve, which is what a worker holds when the
#                   database firewall or the storage account says no
#
# There is also a control that runs the same command line where the application
# is not, because that is the state of a container started before the first zip
# has landed and its log is easy to mistake for a broken portal.
#
# Usage: ./scripts/app-self-test.sh
# Exits nonzero if any assertion fails.
# -----------------------------------------------------------------------------

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JOURNEY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${JOURNEY_DIR}/app"
WEBAPP_BICEP="${JOURNEY_DIR}/bicep/modules/webapp.bicep"

WORK="$(mktemp -d)"
ROOT="${WORK}/wwwroot"
VENV="${WORK}/antenv"
SCRATCH_HOME="${WORK}/home"
mkdir -p "$ROOT" "$SCRATCH_HOME"

PASS=0
FAIL=0
SKIP=0
pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}
skip() {
  echo "SKIP  $1"
  SKIP=$((SKIP + 1))
}

GUNICORN_PID=""
cleanup() {
  [[ -n "$GUNICORN_PID" ]] && kill -9 "$GUNICORN_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

echo "Self-testing the azure/j8-clickops-partial-iac portal (no Azure calls)"
echo ""

# ---- the archive the platform is handed ---------------------------------------
echo "--- archive: what Oryx is given ---"
if python3 "${SCRIPT_DIR}/package-app.py" "$APP_DIR" "${WORK}/app.zip" >/dev/null; then
  pass "scripts/package-app.py built the archive"
else
  echo "FATAL: could not package ${APP_DIR}" >&2
  exit 1
fi
(cd "$ROOT" && unzip -q "${WORK}/app.zip") || {
  echo "FATAL: could not unpack the archive" >&2
  exit 1
}

# Oryx installs from a requirements.txt at the ROOT of the archive and nowhere
# else. A portal reorganised into a subdirectory would still import locally and
# would still deploy — it would just arrive with nothing installed.
if [[ -f "${ROOT}/requirements.txt" ]]; then
  pass "requirements.txt is at the archive root, where Oryx looks for it"
else
  fail "requirements.txt is NOT at the archive root — Oryx will install nothing"
fi

if [[ ! -d "${ROOT}/.venv" && ! -d "${ROOT}/venv" ]]; then
  pass "no local virtual environment was packaged"
else
  fail "a virtual environment was packaged into the archive"
fi

# ---- the command line the platform runs ---------------------------------------
TEMPLATE_COMMAND="$(sed -n "s/^ *appCommandLine: '\(.*\)'$/\1/p" "$WEBAPP_BICEP" | head -1)"
if [[ -n "$TEMPLATE_COMMAND" ]]; then
  pass "read the startup command from bicep/modules/webapp.bicep"
  echo "      ${TEMPLATE_COMMAND}"
else
  echo "FATAL: no appCommandLine found in ${WEBAPP_BICEP}" >&2
  exit 1
fi

# Last token of the startup command, e.g. portal:app
WSGI_TARGET="${TEMPLATE_COMMAND##* }"
WSGI_MODULE="${WSGI_TARGET%%:*}"
WSGI_ATTR="${WSGI_TARGET##*:}"

if [[ "$TEMPLATE_COMMAND" == gunicorn\ * ]]; then
  pass "the startup command runs gunicorn"
else
  fail "the startup command does not start with gunicorn: ${TEMPLATE_COMMAND}"
fi

# ---- dependencies --------------------------------------------------------------
echo ""
echo "--- environment: a fresh install of the pinned requirements ---"
if python3 -m venv "$VENV" >/dev/null 2>&1; then
  pass "created a throwaway virtual environment"
else
  echo "FATAL: could not create ${VENV}" >&2
  exit 1
fi
if "${VENV}/bin/pip" install --quiet --disable-pip-version-check -r "${ROOT}/requirements.txt"; then
  pass "every pinned requirement installed from the archive's requirements.txt"
else
  fail "the pinned requirements did NOT install — the platform build would fail here too"
  echo ""
  echo "------------------------------------------------------------"
  echo "PASS ${PASS}   FAIL ${FAIL}   SKIP ${SKIP}"
  echo "app-self-test FAILED"
  exit 1
fi

# Does the module path in the template resolve against the unpacked archive?
# This is the check that a renamed package or a moved entry point fails.
if (cd "$ROOT" && "${VENV}/bin/python" -c "
import sys
mod = __import__('${WSGI_MODULE}')
sys.exit(0 if hasattr(mod, '${WSGI_ATTR}') else 1)
" >/dev/null 2>&1); then
  pass "${WSGI_TARGET} resolves from the archive root"
else
  fail "${WSGI_TARGET} does NOT resolve from the archive root — the worker cannot start"
fi

# ---- the same command line with nothing to run ------------------------------------
# A site is created with a startup command before it has any code, so its first
# container starts have nothing to import and cannot succeed. A first deployment
# leaves two or three of them in the platform's log, all before the zip arrives,
# and reading one of those as the reason a deployment failed costs an estate.
# This is what they look like, checked here so the shape is not guesswork: the
# same command line, run where the application is not, gives up and names the
# module it could not import.
echo ""
echo "--- control: the same command line with no application present ---"
EMPTY_ROOT="${WORK}/empty"
EMPTY_LOG="${WORK}/empty-boot.log"
mkdir -p "$EMPTY_ROOT"
EMPTY_PORT="$(free_port)"
(
  cd "$EMPTY_ROOT" || exit 1
  HOME="$SCRATCH_HOME" bash -c \
    "exec ${VENV}/bin/${TEMPLATE_COMMAND/--bind=0.0.0.0:8000/--bind=127.0.0.1:${EMPTY_PORT}}"
) >"$EMPTY_LOG" 2>&1 &
GUNICORN_PID=$!

EMPTY_WAITED=0
while ((EMPTY_WAITED < 60)) && kill -0 "$GUNICORN_PID" 2>/dev/null; do
  sleep 1
  EMPTY_WAITED=$((EMPTY_WAITED + 1))
done

if kill -0 "$GUNICORN_PID" 2>/dev/null; then
  kill -9 "$GUNICORN_PID" 2>/dev/null
  GUNICORN_PID=""
  fail "with no application present the startup command kept running for ${EMPTY_WAITED}s"
else
  wait "$GUNICORN_PID"
  EMPTY_RC=$?
  GUNICORN_PID=""
  if ((EMPTY_RC != 0)) && grep -q "No module named '${WSGI_MODULE}'" "$EMPTY_LOG"; then
    pass "with nothing to import it exits ${EMPTY_RC} saying No module named '${WSGI_MODULE}'"
  else
    fail "with nothing to import the failure was not the expected one (exit ${EMPTY_RC})"
    echo "      ---- last 20 lines ----"
    tail -20 "$EMPTY_LOG" 2>/dev/null | sed 's/^/      /'
    echo "      -----------------------"
  fi
fi

# ---- one posture ----------------------------------------------------------------
# start_app <port> <extra env assignments...>; leaves GUNICORN_PID set.
# Returns 0 once the worker answers anything at all, 1 if it never does.
BOOT_DEADLINE=120
PROBE_TIMEOUT=60

start_app() {
  local port="$1"
  shift
  local log="${WORK}/app-${port}.log"
  : >"$log"

  # The template's command line, with only the bind rewritten and gunicorn taken
  # from the throwaway environment. Every other flag is the platform's.
  local command_line="${TEMPLATE_COMMAND/--bind=0.0.0.0:8000/--bind=127.0.0.1:${port}}"
  command_line="${VENV}/bin/${command_line}"

  (
    cd "$ROOT" || exit 1
    # Nothing here should be able to reach a signed-in session on this machine.
    env -u AZURE_CLIENT_ID -u AZURE_TENANT_ID -u AZURE_CLIENT_SECRET \
      -u AZURE_USERNAME -u AZURE_PASSWORD -u AZURE_CLIENT_CERTIFICATE_PATH \
      -u MSI_ENDPOINT -u IDENTITY_ENDPOINT -u IDENTITY_HEADER \
      HOME="$SCRATCH_HOME" \
      AZURE_CONFIG_DIR="${SCRATCH_HOME}/.azure" \
      PYTHONUNBUFFERED=1 \
      "$@" \
      bash -c "exec ${command_line}"
  ) >"$log" 2>&1 &
  GUNICORN_PID=$!

  local waited=0
  while ((waited < BOOT_DEADLINE)); do
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$PROBE_TIMEOUT" \
      "http://127.0.0.1:${port}/health" 2>/dev/null)
    if [[ -n "$code" && "$code" != "000" ]]; then
      return 0
    fi
    kill -0 "$GUNICORN_PID" 2>/dev/null || return 1
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

stop_app() {
  [[ -n "$GUNICORN_PID" ]] && kill -TERM "$GUNICORN_PID" 2>/dev/null
  sleep 1
  [[ -n "$GUNICORN_PID" ]] && kill -9 "$GUNICORN_PID" 2>/dev/null
  GUNICORN_PID=""
}

dump_log() {
  echo "      ---- last 20 lines of the worker log ----"
  tail -20 "${WORK}/app-${1}.log" 2>/dev/null | sed 's/^/      /'
  echo "      -----------------------------------------"
}

# ---- posture 1: nothing configured -----------------------------------------------
echo ""
echo "--- posture 1: bare (no settings delivered yet) ---"
PORT_BARE="$(free_port)"
if start_app "$PORT_BARE"; then
  pass "the worker becomes ready with nothing configured"
  BODY=$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_BARE}/health" 2>/dev/null || echo "")
  if grep -q '"status"' <<<"$BODY"; then
    pass "/health answers with a JSON body"
  else
    fail "/health did not answer with JSON (got: ${BODY:0:160})"
  fi
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_BARE}/" 2>/dev/null)
  if [[ "$CODE" == "200" ]]; then
    pass "the front page answers 200 with no database behind it"
  else
    fail "the front page returned ${CODE}, expected 200"
  fi
else
  fail "the worker never became ready within ${BOOT_DEADLINE}s with nothing configured"
  dump_log "$PORT_BARE"
fi
stop_app

# ---- posture 2: configured, unreachable -------------------------------------------
# The shape a worker is in when the settings have arrived and the endpoints have
# not: a firewall that has not been opened, or a storage account that refuses.
echo ""
echo "--- posture 2: both dependencies configured but unreachable ---"
PORT_UNREACHABLE="$(free_port)"
FAKE_KEY="$(printf 'app-self-test-key-not-a-real-credential0' | base64 | tr -d '\n')"
FAKE_PASSWORD='app-self-test-not-a-real-password'
SQL_CONN="Server=tcp:cpi-sql-unreachable.database.windows.net,1433;Initial Catalog=cpiportal;Persist Security Info=False;User ID=cpiadmin;Password=${FAKE_PASSWORD};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
BLOB_CONN="DefaultEndpointsProtocol=https;AccountName=cpiportalunreachable;AccountKey=${FAKE_KEY};EndpointSuffix=core.windows.net"

if start_app "$PORT_UNREACHABLE" \
  SQLAZURECONNSTR_PortalDb="$SQL_CONN" \
  AZURE_STORAGE_CONNECTION_STRING="$BLOB_CONN" \
  CPI_STORAGE_ACCOUNT=cpiportalunreachable \
  CPI_DOCUMENTS_CONTAINER=documents \
  CPI_SQL_DATABASE=cpiportal; then
  pass "the worker becomes ready with both endpoints unreachable"

  # How long the platform's health probe waits on a portal whose dependencies are
  # both down. Left unbounded, SDK defaults turn this into minutes and the
  # platform recycles the instance while it is still answering.
  START=$(date +%s)
  BODY=$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_UNREACHABLE}/health" 2>/dev/null || echo "")
  ELAPSED=$(($(date +%s) - START))
  if grep -q '"status": *"degraded"' <<<"$BODY"; then
    pass "/health reports degraded rather than failing"
  else
    fail "/health did not report degraded (got: ${BODY:0:200})"
  fi
  if ((ELAPSED <= 45)); then
    pass "/health answered in ${ELAPSED}s, inside the platform's probe budget"
  else
    fail "/health took ${ELAPSED}s with both dependencies down — the probe budget is 45s"
  fi

  CHECK=$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_UNREACHABLE}/admin/azure-check" 2>/dev/null || echo "")
  if grep -q '"all_ok": *false' <<<"$CHECK"; then
    pass "/admin/azure-check answers and reports not-all-ok"
  else
    fail "/admin/azure-check did not answer with all_ok false (got: ${CHECK:0:200})"
  fi

  # The two connection strings are the only credentials the portal holds. Neither
  # may reach a page, including the operational pages that describe them.
  PAGES="${BODY}${CHECK}$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_UNREACHABLE}/" 2>/dev/null || echo "")"
  if grep -qF -e "$FAKE_KEY" -e "$FAKE_PASSWORD" <<<"$PAGES"; then
    fail "a credential from a connection string appeared in a response body"
  else
    pass "no credential from either connection string reached a response"
  fi
else
  fail "the worker never became ready within ${BOOT_DEADLINE}s with the endpoints unreachable"
  dump_log "$PORT_UNREACHABLE"
fi
stop_app

echo ""
echo "------------------------------------------------------------"
echo "PASS ${PASS}   FAIL ${FAIL}   SKIP ${SKIP}"
if [[ "$FAIL" -gt 0 ]]; then
  echo "app-self-test FAILED"
  exit 1
fi
echo "app-self-test OK"
