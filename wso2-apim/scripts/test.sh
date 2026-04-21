#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_commands helm kubectl envsubst
require_vars WSO2_CHART_VERSION ACP_RELEASE_NAME TM_RELEASE_NAME GW_RELEASE_NAME NAMESPACE

"${SCRIPT_DIR}/render-values.sh" "${ENV_FILE}"
"${SCRIPT_DIR}/pull-charts.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/patch-resource-names.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/patch-key-manager-config.sh" "${ENV_FILE}"

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"

helm template "${ACP_RELEASE_NAME}" "${CHART_CACHE_DIR}/wso2am-acp" -n "${NAMESPACE}" -f "${ROOT_DIR}/generated/acp-values.yaml" > "${ROOT_DIR}/generated/acp-rendered.yaml"
helm template "${TM_RELEASE_NAME}" "${CHART_CACHE_DIR}/wso2am-tm" -n "${NAMESPACE}" -f "${ROOT_DIR}/generated/tm-values.yaml" > "${ROOT_DIR}/generated/tm-rendered.yaml"
helm template "${GW_RELEASE_NAME}" "${CHART_CACHE_DIR}/wso2am-universal-gw" -n "${NAMESPACE}" -f "${ROOT_DIR}/generated/gw-values.yaml" > "${ROOT_DIR}/generated/gw-rendered.yaml"

kubectl apply --dry-run=client -f "${ROOT_DIR}/generated/acp-rendered.yaml" >/dev/null
kubectl apply --dry-run=client -f "${ROOT_DIR}/generated/tm-rendered.yaml" >/dev/null
kubectl apply --dry-run=client -f "${ROOT_DIR}/generated/gw-rendered.yaml" >/dev/null

echo "Template rendering and dry-run apply checks passed."
