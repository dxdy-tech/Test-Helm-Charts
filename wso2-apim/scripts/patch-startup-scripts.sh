#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"

if [[ -z "${POSTGRES_JDBC_URL:-}" ]]; then
  require_vars POSTGRES_JDBC_VERSION
  POSTGRES_JDBC_URL="https://jdbc.postgresql.org/download/postgresql-${POSTGRES_JDBC_VERSION}.jar"
fi

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"
TARGET_SCRIPTS=(
  "${CHART_CACHE_DIR}/wso2am-acp/templates/control-plane/wso2am-cp-conf-entrypoint.yaml"
  "${CHART_CACHE_DIR}/wso2am-tm/templates/traffic-manager/wso2am-tm-conf-entrypoint.yaml"
  "${CHART_CACHE_DIR}/wso2am-universal-gw/templates/gateway/wso2am-gateway-conf-entrypoint.yaml"
)

inject_block() {
  local indent="${1:-}"

  cat <<EOF | sed "s/^/${indent}/"
# BEGIN POSTGRES JDBC AUTO-INJECT
JDBC_DRIVER_URL="${POSTGRES_JDBC_URL}"
JDBC_DRIVER_DIR="\${WSO2_SERVER_HOME}/repository/components/lib"
JDBC_DRIVER_FILE="\${JDBC_DRIVER_DIR}/postgresql.jar"

if ! test -f "\${JDBC_DRIVER_FILE}"
then
  echo "Downloading PostgreSQL JDBC driver from \${JDBC_DRIVER_URL}" >&2
  mkdir -p "\${JDBC_DRIVER_DIR}"
  if command -v curl >/dev/null 2>&1
  then
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "\${JDBC_DRIVER_FILE}" "\${JDBC_DRIVER_URL}"
  elif command -v wget >/dev/null 2>&1
  then
    wget -O "\${JDBC_DRIVER_FILE}" "\${JDBC_DRIVER_URL}"
  else
    echo "Neither curl nor wget is available to download PostgreSQL JDBC driver." >&2
    exit 1
  fi
fi
# END POSTGRES JDBC AUTO-INJECT

EOF
}

for target_script in "${TARGET_SCRIPTS[@]}"; do
  if [[ ! -f "${target_script}" ]]; then
    echo "Expected startup script not found: ${target_script}" >&2
    exit 1
  fi

  if grep -q "BEGIN POSTGRES JDBC AUTO-INJECT" "${target_script}"; then
    continue
  fi

  temp_file="$(mktemp)"
  inserted=false

  while IFS= read -r line; do
    if [[ "${inserted}" == "false" && "${line}" == *"# start WSO2 Carbon server"* ]]; then
      indent="$(printf '%s' "${line}" | sed -E 's/^([[:space:]]*).*/\1/')"
      inject_block "${indent}" >> "${temp_file}"
      inserted=true
    fi
    printf '%s\n' "${line}" >> "${temp_file}"
  done < "${target_script}"

  if [[ "${inserted}" != "true" ]]; then
    rm -f "${temp_file}"
    echo "Unable to inject JDBC download block in ${target_script}" >&2
    exit 1
  fi

  chmod --reference="${target_script}" "${temp_file}"
  mv "${temp_file}" "${target_script}"
done

echo "Patched startup scripts with PostgreSQL JDBC auto-download block."
