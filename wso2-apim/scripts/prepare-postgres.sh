#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
require_vars DB_HOST DB_PORT DB_USERNAME DB_PASSWORD APIM_DB_NAME SHARED_DB_NAME

PG_ADMIN_USER="${PG_ADMIN_USER:-${DB_USERNAME}}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-${DB_PASSWORD}}"
DB_PREPARE_MODE="${DB_PREPARE_MODE:-local}"

duration_to_seconds() {
  local raw="${1:-300s}"
  if [[ "${raw}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${raw}"
    return
  fi
  if [[ "${raw}" =~ ^([0-9]+)s$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "${raw}" =~ ^([0-9]+)m$ ]]; then
    printf '%s\n' "$((BASH_REMATCH[1] * 60))"
    return
  fi
  if [[ "${raw}" =~ ^([0-9]+)h$ ]]; then
    printf '%s\n' "$((BASH_REMATCH[1] * 3600))"
    return
  fi

  echo "Unsupported DB_PREPARE_TIMEOUT format: ${raw}. Use number, Ns, Nm, or Nh." >&2
  exit 1
}

run_prepare_sql_local() {
  require_commands psql

  export PGPASSWORD="${PG_ADMIN_PASSWORD}"

  psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${PG_ADMIN_USER}" -d postgres \
    -v ON_ERROR_STOP=1 \
    -v db_user="${DB_USERNAME}" \
    -v db_password="${DB_PASSWORD}" \
    -v apim_db_name="${APIM_DB_NAME}" \
    -v shared_db_name="${SHARED_DB_NAME}" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user')
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'apim_db_name', :'db_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'apim_db_name')
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'shared_db_name', :'db_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'shared_db_name')
\gexec

SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'apim_db_name', :'db_user')\gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'shared_db_name', :'db_user')\gexec
SQL

  unset PGPASSWORD
}

run_prepare_sql_cluster() {
  ensure_kubeconfig_default
  require_vars NAMESPACE
  require_commands kubectl

  local image="${DB_PREPARE_IMAGE:-postgres:16}"
  local timeout="${DB_PREPARE_TIMEOUT:-300s}"
  local timeout_seconds
  timeout_seconds="$(duration_to_seconds "${timeout}")"
  local pod_name="${DB_PREPARE_POD_NAME:-apim-db-prepare-$(date +%s)}"
  local cleanup_pod="${DB_PREPARE_CLEANUP_POD:-true}"
  local start_ts
  local now_ts
  local phase
  local pod_cmd=""
  local pod_overrides='{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}'

  read -r -d '' pod_cmd <<'PODCMD' || true
psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_ADMIN_USER" -d postgres \
  -v ON_ERROR_STOP=1 \
  -v db_user="$DB_USERNAME" \
  -v db_password="$DB_PASSWORD" \
  -v apim_db_name="$APIM_DB_NAME" \
  -v shared_db_name="$SHARED_DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user')
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'apim_db_name', :'db_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'apim_db_name')
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'shared_db_name', :'db_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'shared_db_name')
\gexec

SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'apim_db_name', :'db_user')\gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'shared_db_name', :'db_user')\gexec
SQL
PODCMD

  kubectl -n "${NAMESPACE}" delete pod "${pod_name}" --ignore-not-found >/dev/null

  kubectl -n "${NAMESPACE}" run "${pod_name}" \
    --image="${image}" \
    --restart=Never \
    --overrides="${pod_overrides}" \
    --env="DB_HOST=${DB_HOST}" \
    --env="DB_PORT=${DB_PORT}" \
    --env="PG_ADMIN_USER=${PG_ADMIN_USER}" \
    --env="DB_USERNAME=${DB_USERNAME}" \
    --env="DB_PASSWORD=${DB_PASSWORD}" \
    --env="APIM_DB_NAME=${APIM_DB_NAME}" \
    --env="SHARED_DB_NAME=${SHARED_DB_NAME}" \
    --env="PGPASSWORD=${PG_ADMIN_PASSWORD}" \
    --command -- sh -ceu "${pod_cmd}"

  start_ts="$(date +%s)"
  while true; do
    phase="$(kubectl -n "${NAMESPACE}" get pod "${pod_name}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "${phase}" in
      Succeeded)
        break
        ;;
      Failed)
        kubectl -n "${NAMESPACE}" logs "${pod_name}" || true
        kubectl -n "${NAMESPACE}" describe pod "${pod_name}" || true
        echo "In-cluster database preparation failed in pod ${pod_name}." >&2
        exit 1
        ;;
    esac

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_seconds )); then
      kubectl -n "${NAMESPACE}" logs "${pod_name}" || true
      kubectl -n "${NAMESPACE}" describe pod "${pod_name}" || true
      echo "In-cluster database preparation timed out after ${timeout}." >&2
      exit 1
    fi

    sleep 3
  done

  kubectl -n "${NAMESPACE}" logs "${pod_name}"

  if is_true "${cleanup_pod}"; then
    kubectl -n "${NAMESPACE}" delete pod "${pod_name}" --ignore-not-found >/dev/null
  fi
}

case "${DB_PREPARE_MODE}" in
  local)
    run_prepare_sql_local
    ;;
  cluster)
    run_prepare_sql_cluster
    ;;
  *)
    echo "Unsupported DB_PREPARE_MODE: ${DB_PREPARE_MODE}. Use 'local' or 'cluster'." >&2
    exit 1
    ;;
esac

echo "Databases/users prepared."
echo "This step prepares role and databases only."
