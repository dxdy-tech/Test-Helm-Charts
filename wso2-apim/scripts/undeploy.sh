#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_commands helm kubectl
require_vars NAMESPACE ACP_RELEASE_NAME TM_RELEASE_NAME GW_RELEASE_NAME

helm uninstall "${GW_RELEASE_NAME}" -n "${NAMESPACE}" || true
helm uninstall "${TM_RELEASE_NAME}" -n "${NAMESPACE}" || true
helm uninstall "${ACP_RELEASE_NAME}" -n "${NAMESPACE}" || true

if is_true "${DELETE_NAMESPACE:-false}"; then
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true
fi

echo "Undeploy completed."
