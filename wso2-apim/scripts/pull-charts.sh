#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
require_commands helm
require_vars WSO2_CHART_VERSION

if ! helm repo list | awk 'NR>1 {print $1}' | grep -qx wso2; then
  helm repo add wso2 https://helm.wso2.com
fi
helm repo update

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"
rm -rf "${CHART_CACHE_DIR}"
mkdir -p "${CHART_CACHE_DIR}"

helm pull wso2/wso2am-acp --version "${WSO2_CHART_VERSION}" --untar --untardir "${CHART_CACHE_DIR}"
helm pull wso2/wso2am-tm --version "${WSO2_CHART_VERSION}" --untar --untardir "${CHART_CACHE_DIR}"
helm pull wso2/wso2am-universal-gw --version "${WSO2_CHART_VERSION}" --untar --untardir "${CHART_CACHE_DIR}"

echo "Pulled charts to ${CHART_CACHE_DIR}."
