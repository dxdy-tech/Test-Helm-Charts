#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_vars DB_HOST DB_PORT DB_USERNAME DB_PASSWORD APIM_DB_NAME SHARED_DB_NAME NAMESPACE \
  ACP_CUSTOM_IMAGE_REPOSITORY ACP_IMAGE_TAG

PG_ADMIN_USER="${PG_ADMIN_USER:-${DB_USERNAME}}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-${DB_PASSWORD}}"
SCHEMA_APPLY_MODE="${SCHEMA_APPLY_MODE:-${DB_PREPARE_MODE:-cluster}}"

resolve_source_image() {
  if [[ -n "${SCHEMA_SOURCE_IMAGE:-}" ]]; then
    printf '%s\n' "${SCHEMA_SOURCE_IMAGE}"
    return
  fi

  # Use the custom ACP image (built from WSO2 source; contains all server files including dbscripts)
  local repo="${ACP_CUSTOM_IMAGE_REPOSITORY}"
  local tag="${ACP_IMAGE_TAG}"

  if [[ -n "${CUSTOM_IMAGE_REGISTRY:-}" ]]; then
    local first_segment="${repo%%/*}"
    if [[ "${first_segment}" != *.* && "${first_segment}" != *:* && "${first_segment}" != "localhost" ]]; then
      repo="${CUSTOM_IMAGE_REGISTRY}/${repo}"
    fi
  fi

  printf '%s:%s\n' "${repo}" "${tag}"
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

wait_for_pod_phase() {
  local pod_name="${1}"
  local expected_phase="${2}"
  local timeout_seconds="${3}"
  local timeout_human="${4}"
  local start_ts
  local now_ts
  local phase

  start_ts="$(date +%s)"
  while true; do
    phase="$(kubectl -n "${NAMESPACE}" get pod "${pod_name}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"

    if [[ "${phase}" == "${expected_phase}" ]]; then
      return 0
    fi

    if [[ "${phase}" == "Failed" ]]; then
      kubectl -n "${NAMESPACE}" logs "${pod_name}" || true
      kubectl -n "${NAMESPACE}" describe pod "${pod_name}" || true
      echo "Pod ${pod_name} failed while waiting for phase ${expected_phase}." >&2
      exit 1
    fi

    now_ts="$(date +%s)"
    if (( now_ts - start_ts >= timeout_seconds )); then
      kubectl -n "${NAMESPACE}" logs "${pod_name}" || true
      kubectl -n "${NAMESPACE}" describe pod "${pod_name}" || true
      echo "Timed out after ${timeout_human} waiting for pod ${pod_name} phase ${expected_phase}." >&2
      exit 1
    fi

    sleep 3
  done
}

extract_schema_from_image() {
  local source_image="${1}"
  local out_shared_sql="${2}"
  local out_apim_sql="${3}"

  local timeout="${DB_PREPARE_TIMEOUT:-300s}"
  local timeout_seconds
  timeout_seconds="$(duration_to_seconds "${timeout}")"
  local pod_name="${SCHEMA_EXPORT_POD_NAME:-apim-schema-export-$(date +%s)}"
  local cleanup_pod="${DB_PREPARE_CLEANUP_POD:-true}"
  local image_pull_secret_name="${IMAGE_PULL_SECRET_NAME:-apim-image-registry-auth}"
  local pod_overrides
  printf -v pod_overrides '{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}},"spec":{"imagePullSecrets":[{"name":"%s"}]}}' "${image_pull_secret_name}"

  local pod_cmd=""
  read -r -d '' pod_cmd <<'PODCMD' || true
find_base_dir() {
  for base in \
    "/home/wso2carbon/wso2am-acp-${ACP_IMAGE_TAG}" \
    "/home/wso2carbon/wso2am-${ACP_IMAGE_TAG}" \
    "/home/wso2carbon/wso2am"; do
    if [ -f "$base/dbscripts/postgresql.sql" ] && [ -f "$base/dbscripts/apimgt/postgresql.sql" ]; then
      echo "$base"
      return 0
    fi
  done

  fallback="$(find /home -maxdepth 5 -type f -path '*/dbscripts/postgresql.sql' 2>/dev/null | head -n 1 || true)"
  if [ -n "$fallback" ]; then
    dirname "$(dirname "$fallback")"
    return 0
  fi

  return 1
}

base_dir="$(find_base_dir)" || {
  echo "Unable to locate dbscripts in APIM image." >&2
  exit 1
}

shared_sql="$base_dir/dbscripts/postgresql.sql"
apim_sql="$base_dir/dbscripts/apimgt/postgresql.sql"

echo "SCHEMA_SHARED_BEGIN"
cat "$shared_sql"
echo "SCHEMA_SHARED_END"
echo "SCHEMA_APIM_BEGIN"
cat "$apim_sql"
echo "SCHEMA_APIM_END"
PODCMD

  kubectl -n "${NAMESPACE}" delete pod "${pod_name}" --ignore-not-found >/dev/null

  kubectl -n "${NAMESPACE}" run "${pod_name}" \
    --image="${source_image}" \
    --restart=Never \
    --overrides="${pod_overrides}" \
    --env="ACP_IMAGE_TAG=${ACP_IMAGE_TAG}" \
    --command -- sh -ceu "${pod_cmd}"

  wait_for_pod_phase "${pod_name}" "Succeeded" "${timeout_seconds}" "${timeout}"

  local raw_out
  raw_out="$(mktemp)"
  kubectl -n "${NAMESPACE}" logs "${pod_name}" > "${raw_out}"

  awk '/^SCHEMA_SHARED_BEGIN$/{capture=1;next} /^SCHEMA_SHARED_END$/{capture=0} capture{print}' "${raw_out}" > "${out_shared_sql}"
  awk '/^SCHEMA_APIM_BEGIN$/{capture=1;next} /^SCHEMA_APIM_END$/{capture=0} capture{print}' "${raw_out}" > "${out_apim_sql}"

  rm -f "${raw_out}"

  if [[ ! -s "${out_shared_sql}" || ! -s "${out_apim_sql}" ]]; then
    echo "Extracted schema SQL is empty. Verify SCHEMA_SOURCE_IMAGE and APIM tag." >&2
    exit 1
  fi

  if is_true "${cleanup_pod}"; then
    kubectl -n "${NAMESPACE}" delete pod "${pod_name}" --ignore-not-found >/dev/null
  fi
}

apply_schema_local() {
  local shared_sql="${1}"
  local apim_sql="${2}"

  require_commands psql

  export PGPASSWORD="${PG_ADMIN_PASSWORD}"

  psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${PG_ADMIN_USER}" -d "${SHARED_DB_NAME}" -v ON_ERROR_STOP=1 -f "${shared_sql}"
  psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${PG_ADMIN_USER}" -d "${APIM_DB_NAME}" -v ON_ERROR_STOP=1 -f "${apim_sql}"

  unset PGPASSWORD
}

apply_schema_cluster() {
  local shared_sql="${1}"
  local apim_sql="${2}"

  require_commands kubectl

  local image="${DB_PREPARE_IMAGE:-postgres:16}"
  local timeout="${DB_PREPARE_TIMEOUT:-300s}"
  local timeout_seconds
  timeout_seconds="$(duration_to_seconds "${timeout}")"
  local pod_name="${SCHEMA_APPLY_POD_NAME:-apim-schema-apply-$(date +%s)}"
  local cleanup_pod="${DB_PREPARE_CLEANUP_POD:-true}"
  local pod_overrides='{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}'

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
    --command -- sh -ceu 'sleep 3600'

  wait_for_pod_phase "${pod_name}" "Running" "${timeout_seconds}" "${timeout}"

  kubectl cp "${shared_sql}" "${NAMESPACE}/${pod_name}:/tmp/shared-postgresql.sql"
  kubectl cp "${apim_sql}" "${NAMESPACE}/${pod_name}:/tmp/apimgt-postgresql.sql"

  kubectl -n "${NAMESPACE}" exec "${pod_name}" -- sh -ceu 'psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_ADMIN_USER" -d "$SHARED_DB_NAME" -v ON_ERROR_STOP=1 -f /tmp/shared-postgresql.sql'
  kubectl -n "${NAMESPACE}" exec "${pod_name}" -- sh -ceu 'psql -h "$DB_HOST" -p "$DB_PORT" -U "$PG_ADMIN_USER" -d "$APIM_DB_NAME" -v ON_ERROR_STOP=1 -f /tmp/apimgt-postgresql.sql'

  if is_true "${cleanup_pod}"; then
    kubectl -n "${NAMESPACE}" delete pod "${pod_name}" --ignore-not-found >/dev/null
  fi
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

source_image="$(resolve_source_image)"
shared_schema_sql="${tmp_dir}/shared-postgresql.sql"
apim_schema_sql="${tmp_dir}/apimgt-postgresql.sql"

extract_schema_from_image "${source_image}" "${shared_schema_sql}" "${apim_schema_sql}"

case "${SCHEMA_APPLY_MODE}" in
  local)
    apply_schema_local "${shared_schema_sql}" "${apim_schema_sql}"
    ;;
  cluster)
    apply_schema_cluster "${shared_schema_sql}" "${apim_schema_sql}"
    ;;
  *)
    echo "Unsupported SCHEMA_APPLY_MODE: ${SCHEMA_APPLY_MODE}. Use 'local' or 'cluster'." >&2
    exit 1
    ;;
esac

echo "WSO2 PostgreSQL schema bootstrap completed."
