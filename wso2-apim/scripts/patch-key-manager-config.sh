#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"
KEY_MANAGER_FLAG_LINE="enable_application_scopes_for_resident_km = true"
TARGET_FILES=(
  "${CHART_CACHE_DIR}/wso2am-acp/confs/instance-1/deployment.toml"
  "${CHART_CACHE_DIR}/wso2am-acp/confs/instance-2/deployment.toml"
  "${CHART_CACHE_DIR}/wso2am-tm/confs/instance-1/deployment.toml"
  "${CHART_CACHE_DIR}/wso2am-tm/confs/instance-2/deployment.toml"
  "${CHART_CACHE_DIR}/wso2am-universal-gw/confs/deployment.toml"
)

for target_file in "${TARGET_FILES[@]}"; do
  if [[ ! -f "${target_file}" ]]; then
    echo "Expected deployment.toml not found: ${target_file}" >&2
    exit 1
  fi

  if grep -q "${KEY_MANAGER_FLAG_LINE}" "${target_file}"; then
    continue
  fi

  temp_file="$(mktemp)"

  awk -v inserted_line="${KEY_MANAGER_FLAG_LINE}" '
    {
      print $0
      if ($0 ~ /^\[apim\.key_manager\]$/ && inserted == 0) {
        print inserted_line
        inserted = 1
      }
    }
    END {
      if (inserted == 0) {
        exit 2
      }
    }
  ' "${target_file}" > "${temp_file}" || {
    rm -f "${temp_file}"
    echo "Unable to inject key manager setting into ${target_file}" >&2
    exit 1
  }

  chmod --reference="${target_file}" "${temp_file}"
  mv "${temp_file}" "${target_file}"
done

echo "Patched deployment.toml files with key manager application scopes setting."
