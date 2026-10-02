#!/usr/bin/env bash
# app-self-test.sh — run the storefront locally, in the postures it actually
# meets on App Service, and assert it stays up in all of them.
# -----------------------------------------------------------------------------
# This is a laptop test. It talks to no Azure subscription and needs no
# credentials. It exists because the shop's dependencies (a vault, a blob
# account, a database) are all optional at runtime by design, and the only way
# to know the fail-soft paths really are soft is to take each one away.
#
# Postures:
#   1 bare          nothing configured — the laptop case
#   2 unreachable   vault and blob endpoints configured but unresolvable, and
#                   PWA_CHECKOUT_SIGNING_KEY carrying an unresolved Key Vault
#                   reference instead of a secret, which is what a worker is
#                   handed when the platform cannot read the vault for it
#   3 database      posture 2 with a real PostgreSQL behind it, so /health can
#                   be checked for the 200-and-degraded answer that a shop with
#                   a working catalogue but no vault is supposed to give
#
# Posture 3 needs docker and is skipped, not failed, without it.
#
# Every posture runs under a scratch HOME with AZURE_* cleared: the credential
# chain must not be able to reach a signed-in az session on the machine running
# this. A token minted against a real tenant here would make the result a lie.
#
# Usage: ./scripts/app-self-test.sh
# Exits nonzero if any assertion fails.
# -----------------------------------------------------------------------------

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/../app"
VENV="${APP_DIR}/.venv"
WORK="$(mktemp -d)"
SCRATCH_HOME="${WORK}/home"
mkdir -p "$SCRATCH_HOME"

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

PG_CONTAINER=""
GUNICORN_PID=""
cleanup() {
  [[ -n "$GUNICORN_PID" ]] && kill -9 "$GUNICORN_PID" 2>/dev/null
  [[ -n "$PG_CONTAINER" ]] && docker rm -f "$PG_CONTAINER" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

# A previous run that was killed outright leaves its container behind, and the
# port it holds is enough to make this run look like docker is broken.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker ps -aq --filter "name=pwa-selftest-" | xargs -r docker rm -f >/dev/null 2>&1
fi

# Ports are picked at run time so two of these can run side by side.
free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}
PORT_BARE="$(free_port)"
PORT_UNREACHABLE="$(free_port)"
PORT_DATABASE="$(free_port)"
PORT_PG="$(free_port)"

# ---- dependencies -------------------------------------------------------------
if [[ ! -x "${VENV}/bin/gunicorn" ]]; then
  echo ">>> Building the local virtual environment"
  python3 -m venv "$VENV" || {
    echo "FATAL: could not create ${VENV}" >&2
    exit 1
  }
  "${VENV}/bin/pip" install --quiet --disable-pip-version-check -r "${APP_DIR}/requirements.txt" || {
    echo "FATAL: could not install ${APP_DIR}/requirements.txt" >&2
    exit 1
  }
fi

# ---- one posture --------------------------------------------------------------
# start_app <port> <extra env assignments...>; leaves GUNICORN_PID set.
# Returns 0 once /health answers anything at all, 1 if it never does.
# A worker answering slowly is alive; only one that answers not at all is not.
# The probes reach out to Azure endpoints, so a single /health can legitimately
# take tens of seconds when those endpoints are the unreachable ones.
BOOT_DEADLINE=150
PROBE_TIMEOUT=45

start_app() {
  local port="$1"
  shift
  local log="${WORK}/app-${port}.log"
  : >"$log"

  (
    cd "$APP_DIR" || exit 1
    # The credential chain must not find a real session: scratch HOME, and the
    # CLI's own config dir pointed somewhere empty.
    env -u AZURE_CLIENT_ID -u AZURE_TENANT_ID -u AZURE_CLIENT_SECRET \
      -u AZURE_USERNAME -u AZURE_PASSWORD -u AZURE_CLIENT_CERTIFICATE_PATH \
      -u MSI_ENDPOINT -u IDENTITY_ENDPOINT -u IDENTITY_HEADER \
      HOME="$SCRATCH_HOME" \
      AZURE_CONFIG_DIR="${SCRATCH_HOME}/.azure" \
      PYTHONUNBUFFERED=1 \
      DJANGO_DEBUG=0 \
      DJANGO_SECRET_KEY=app-self-test \
      DJANGO_ALLOWED_HOSTS='*' \
      "$@" \
      "${VENV}/bin/gunicorn" --bind=127.0.0.1:"${port}" --timeout 120 \
      --access-logfile - --error-logfile - webshop.wsgi:application
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
    waited=$((waited + 5))
  done
  return 1
}

stop_app() {
  [[ -n "$GUNICORN_PID" ]] && kill -TERM "$GUNICORN_PID" 2>/dev/null
  sleep 1
  [[ -n "$GUNICORN_PID" ]] && kill -9 "$GUNICORN_PID" 2>/dev/null
  GUNICORN_PID=""
}

# A worker that never answered is only useful as a report if you can see why.
dump_log() {
  local log="${WORK}/app-${1}.log"
  echo "      ---- last 15 lines of the worker log ----"
  tail -15 "$log" 2>/dev/null | sed 's/^/      /'
  echo "      -----------------------------------------"
}

echo "Self-testing the azure/j2-paas-web-app storefront (no Azure calls)"
echo ""

# ---- posture 1: nothing configured ---------------------------------------------
echo "--- posture 1: bare (no Azure settings) ---"
if start_app "$PORT_BARE" PWA_DB_HOST=127.0.0.1 PWA_DB_PORT=1 PWA_DB_PASSWORD=none; then
  pass "worker becomes ready with nothing configured"
  BODY=$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_BARE}/health" 2>/dev/null || echo "")
  if grep -q '"status"' <<<"$BODY"; then
    pass "/health answers with a JSON body"
  else
    fail "/health did not answer with JSON (got: ${BODY:0:160})"
  fi
else
  fail "worker never became ready within ${BOOT_DEADLINE}s with nothing configured"
  dump_log "$PORT_BARE"
fi
stop_app
echo ""

# ---- posture 2: dependencies configured but unreachable ------------------------
# This is the shape of a deployment whose identity cannot read the vault: the
# endpoints are set, and the signing-key setting holds the reference itself
# rather than the secret it points at.
echo "--- posture 2: vault and blob configured but unreachable ---"
UNRESOLVED_REF='@Microsoft.KeyVault(SecretUri=https://pwa-kv-unreachable.vault.azure.net/secrets/checkout-webhook-signing-key/)'
if start_app "$PORT_UNREACHABLE" \
  PWA_DB_HOST=127.0.0.1 PWA_DB_PORT=1 PWA_DB_PASSWORD=none \
  PWA_KEY_VAULT_URI='https://pwa-kv-unreachable.vault.azure.net/' \
  PWA_CHECKOUT_SECRET_NAME=checkout-webhook-signing-key \
  PWA_CHECKOUT_SIGNING_KEY="$UNRESOLVED_REF" \
  PWA_MEDIA_ACCOUNT=pwamediaunreachable \
  PWA_MEDIA_BLOB_ENDPOINT='https://pwamediaunreachable.blob.core.windows.net/' \
  PWA_MEDIA_CONTAINER=media; then
  pass "worker becomes ready with the vault and blob account unreachable"

  BODY=$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_UNREACHABLE}/health" 2>/dev/null || echo "")
  if grep -q '"status": *"degraded"' <<<"$BODY"; then
    pass "/health reports degraded rather than failing"
  else
    fail "/health did not report degraded (got: ${BODY:0:200})"
  fi

  CHECK=$(curl -s --max-time 120 "http://127.0.0.1:${PORT_UNREACHABLE}/admin/azure-check" 2>/dev/null || echo "")
  if grep -q '"all_ok": *false' <<<"$CHECK"; then
    pass "/admin/azure-check answers and reports not-all-ok"
  else
    fail "/admin/azure-check did not answer with all_ok false (got: ${CHECK:0:200})"
  fi

  # The credential chain must not have found a session on this machine. If it
  # had, managed_identity would be ok and the whole run would be measuring the
  # operator's own login rather than the app.
  if grep -qE '"managed_identity": *\{[^}]*"ok": *false' <<<"$CHECK"; then
    pass "no token was obtained — the credential chain found no local session"
  else
    fail "a token WAS obtained locally; this run measured a real login, not the app"
  fi

  # An unresolved reference is not a signing key. Serving with the literal
  # string in place of the secret would sign checkouts with the reference text.
  KEYSTATE=$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_UNREACHABLE}/health" 2>/dev/null | grep -c 'Microsoft.KeyVault' || true)
  if [[ "$KEYSTATE" == "0" ]]; then
    pass "the unresolved vault reference did not leak into a response"
  else
    fail "an unresolved vault reference appeared in a response body"
  fi
else
  fail "worker never became ready within ${BOOT_DEADLINE}s with the vault unreachable"
  dump_log "$PORT_UNREACHABLE"
fi
stop_app
echo ""

# ---- posture 3: same, with a real database -------------------------------------
echo "--- posture 3: unreachable vault, working database ---"
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  skip "posture 3 (no usable docker for a throwaway PostgreSQL)"
else
  PG_CONTAINER="pwa-selftest-$$"
  PG_PORT="$PORT_PG"
  if docker run -d --rm --name "$PG_CONTAINER" \
    -e POSTGRES_PASSWORD=selftest -e POSTGRES_USER=pwaadmin -e POSTGRES_DB=pwashop \
    -p "127.0.0.1:${PG_PORT}:5432" postgres:16-alpine >/dev/null 2>&1; then

    READY=0
    for _ in $(seq 1 45); do
      if docker exec "$PG_CONTAINER" pg_isready -U pwaadmin -d pwashop >/dev/null 2>&1; then
        READY=1
        break
      fi
      sleep 1
    done

    if [[ "$READY" -eq 1 ]]; then
      (cd "$APP_DIR" && env HOME="$SCRATCH_HOME" DJANGO_SECRET_KEY=app-self-test \
        PWA_DB_HOST=127.0.0.1 PWA_DB_PORT="$PG_PORT" PWA_DB_NAME=pwashop \
        PWA_DB_USER=pwaadmin PWA_DB_PASSWORD=selftest PWA_DB_SSLMODE=disable \
        "${VENV}/bin/python" manage.py migrate --noinput >/dev/null 2>&1) &&
        (cd "$APP_DIR" && env HOME="$SCRATCH_HOME" DJANGO_SECRET_KEY=app-self-test \
          PWA_DB_HOST=127.0.0.1 PWA_DB_PORT="$PG_PORT" PWA_DB_NAME=pwashop \
          PWA_DB_USER=pwaadmin PWA_DB_PASSWORD=selftest PWA_DB_SSLMODE=disable \
          "${VENV}/bin/python" manage.py loaddata seed-data/catalogue.json >/dev/null 2>&1)

      if start_app "$PORT_DATABASE" \
        PWA_DB_HOST=127.0.0.1 PWA_DB_PORT="$PG_PORT" PWA_DB_NAME=pwashop \
        PWA_DB_USER=pwaadmin PWA_DB_PASSWORD=selftest PWA_DB_SSLMODE=disable \
        PWA_KEY_VAULT_URI='https://pwa-kv-unreachable.vault.azure.net/' \
        PWA_CHECKOUT_SECRET_NAME=checkout-webhook-signing-key \
        PWA_CHECKOUT_SIGNING_KEY="$UNRESOLVED_REF" \
        PWA_MEDIA_ACCOUNT=pwamediaunreachable \
        PWA_MEDIA_BLOB_ENDPOINT='https://pwamediaunreachable.blob.core.windows.net/' \
        PWA_MEDIA_CONTAINER=media; then

        CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$PROBE_TIMEOUT" \
          "http://127.0.0.1:${PORT_DATABASE}/health" 2>/dev/null)
        if [[ "$CODE" == "200" ]]; then
          pass "/health returns 200 with a working database and no vault"
        else
          fail "/health returned ${CODE} with a working database, expected 200"
        fi

        BODY=$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_DATABASE}/health" 2>/dev/null || echo "")
        if grep -q '"status": *"degraded"' <<<"$BODY"; then
          pass "/health says degraded while the vault is unreachable"
        else
          fail "/health did not say degraded (got: ${BODY:0:200})"
        fi

        if grep -qE '"database": *\{[^}]*"ok": *true' <<<"$BODY"; then
          pass "/health reports the database healthy"
        else
          fail "/health did not report the database healthy"
        fi

        LIST=$(curl -s --max-time "$PROBE_TIMEOUT" "http://127.0.0.1:${PORT_DATABASE}/" 2>/dev/null || echo "")
        if grep -q "6 items in the catalogue" <<<"$LIST"; then
          pass "catalogue page renders all six products without the vault"
        else
          fail "catalogue page did not render six products"
        fi
      else
        fail "worker never became ready within ${BOOT_DEADLINE}s with a working database"
        dump_log "$PORT_DATABASE"
      fi
      stop_app
    else
      skip "posture 3 (PostgreSQL container never became ready)"
    fi
  else
    skip "posture 3 (could not start a PostgreSQL container)"
  fi
fi

echo ""
echo "------------------------------------------------------------"
echo "PASS ${PASS}   FAIL ${FAIL}   SKIP ${SKIP}"
if [[ "$FAIL" -gt 0 ]]; then
  echo "app-self-test FAILED"
  exit 1
fi
echo "app-self-test OK"
