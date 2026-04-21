#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_vars DB_HOST DB_PORT DB_USERNAME DB_PASSWORD APIM_DB_NAME SHARED_DB_NAME NAMESPACE

PG_ADMIN_USER="${PG_ADMIN_USER:-${DB_USERNAME}}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-${DB_PASSWORD}}"
DB_PREPARE_MODE="${DB_PREPARE_MODE:-cluster}"
SHARED_SENTINEL_TABLE="${SCHEMA_CHECK_SHARED_TABLE:-idn_base_table}"
APIM_SENTINEL_TABLE="${SCHEMA_CHECK_APIM_TABLE:-am_api}"
SCHEMA_MISSING_EXIT_CODE=10

trim() {
  echo "${1:-}" | tr -d '[:space:]'
}

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

schema_ready_or_missing() {
  local shared_state="${1:-f}"
  local apim_state="${2:-f}"

  if [[ "${shared_state}" == "t" && "${apim_state}" == "t" ]]; then
    return 0
  fi

  return "${SCHEMA_MISSING_EXIT_CODE}"
}

check_schema_local() {
  require_commands psql

  export PGPASSWORD="${PG_ADMIN_PASSWORD}"

  local shared_state
  local apim_state

  shared_state="$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${PG_ADMIN_USER}" -d "${SHARED_DB_NAME}" \
    -v ON_ERROR_STOP=1 -tAc "SELECT to_regclass('public.${SHARED_SENTINEL_TABLE}') IS NOT NULL;")"
  apim_state="$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${PG_ADMIN_USER}" -d "${APIM_DB_NAME}" \
    -v ON_ERROR_STOP=1 -tAc "SELECT to_regclass('public.${APIM_SENTINEL_TABLE}') IS NOT NULL;")"

  unset PGPASSWORD

  schema_ready_or_missing "$(trim "${shared_state}")" "$(trim "${apim_state}")"
}

check_schema_cluster() {
  require_commands kubectl

  local image="${DB_PREPARE_IMAGE:-postgres:16}"
  local timeout="${DB_PREPARE_TIMEOUT:-300s}"
  local timeout_seconds
  timeout_seconds="$(duration_to_seconds "${timeout}")"
  local pod_name="${DB_SCHEMA_CHECK_POD_NAME:-apim-schema-check-$(date +%s)}"
  local cleanup_pod="${DB_PREPARE_CLEANUP_POD:-true}"
  local pod_overrides='{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}'
  local start_ts
  local now_ts
  local phase

  local pod_cmd=""
  read -r -d '' pod_cmd <<'PODCMD' || true
shared_state="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_ADMIN_USER" -d "$SHARED_DB_NAME" -v ON_ERROR_STOP=1 -tAc "SELECT to_regclass('public.$SHARED_SENTINEL_TABLE') IS NOT NULL;" | tr -d '[:space:]')"
apim_state="$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_ADMIN_USER" -d "$APIM_DB_NAME" -v ON_ERROR_STOP=1 -tAc "SELECT to_regclass('public.$APIM_SENTINEL_TABLE') IS NOT NULL;" | tr -d '[:space:]')"
echo "SCHEMA_SHARED=${shared_state}"
echo "SCHEMA_APIM=${apim_state}"
PODCMD

  kubectl -n "${NAMESPACE}" delete pod "${pod_name}" --ignore-not-found >/dev/null

  kubectl -n "${NAMESPACE}" run "${pod_name}" \
    --image="${image}" \
    --restart=Never \
    --overrides="${pod_overrides}" \
    --env="DB_HOST=${DB_HOST}" \
    --env="DB_PORT=${DB_PORT}" \
    --env="PG_ADMIN_USER=${PG_ADMIN_USER}" \
    --env="PGPASSWORD=${PG_ADMIN_PASSWORD}" \
    --env="SHARED_DB_NAME=${SHARED_DB_NAME}" \
    --env="APIM_DB_NAME=${APIM_DB_NAME}" \
    --env="SHARED_SENTINEL_TABLE=${SHARED_SENTINEL_TABLE}" \
    --env="APIM_SENTINEL_TABLE=${APIM_SENTINEL_TABLE}" \
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
        echo "In-cluster schema check failed in pod ${pod_name}." >&2
        exit 1
        ;;
    esac

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_seconds )); then
      kubectl -n "${NAMESPACE}" logs "${pod_name}" || true
      kubectl -n "${NAMESPACE}" describe pod "${pod_name}" || true
      echo "In-cluster schema check timed out after ${timeout}." >&2
      exit 1
    fi

    sleep 3
  done

  local logs
  local shared_state
  local apim_state

  logs="$(kubectl -n "${NAMESPACE}" logs "${pod_name}")"
  shared_state="$(printf '%s\n' "${logs}" | awk -F= '/^SCHEMA_SHARED=/{print $2}' | tail -n 1 | tr -d '[:space:]')"
  apim_state="$(printf '%s\n' "${logs}" | awk -F= '/^SCHEMA_APIM=/{print $2}' | tail -n 1 | tr -d '[:space:]')"

  if is_true "${cleanup_pod}"; then
    kubectl -n "${NAMESPACE}" delete pod "${pod_name}" --ignore-not-found >/dev/null
  fi

  schema_ready_or_missing "${shared_state}" "${apim_state}"
}

case "${DB_PREPARE_MODE}" in
  local)
    check_schema_local
    ;;
  cluster)
    check_schema_cluster
    ;;
  *)
    echo "Unsupported DB_PREPARE_MODE: ${DB_PREPARE_MODE}. Use 'local' or 'cluster'." >&2
    exit 1
    ;;
esac

echo "Schema sentinels found in both databases."
