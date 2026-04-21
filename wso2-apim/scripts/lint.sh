#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
require_commands helm envsubst
require_vars WSO2_CHART_VERSION

"${SCRIPT_DIR}/render-values.sh" "${ENV_FILE}"
"${SCRIPT_DIR}/pull-charts.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/patch-resource-names.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/patch-key-manager-config.sh" "${ENV_FILE}"

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"
helm lint "${CHART_CACHE_DIR}/wso2am-acp" -f "${ROOT_DIR}/generated/acp-values.yaml"
helm lint "${CHART_CACHE_DIR}/wso2am-tm" -f "${ROOT_DIR}/generated/tm-values.yaml"
helm lint "${CHART_CACHE_DIR}/wso2am-universal-gw" -f "${ROOT_DIR}/generated/gw-values.yaml"

echo "Helm lint completed."
