#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_commands helm kubectl
require_vars NAMESPACE MI_RELEASE_NAME ICP_RELEASE_NAME

helm uninstall "${MI_RELEASE_NAME}" -n "${NAMESPACE}" || true
helm uninstall "${ICP_RELEASE_NAME}" -n "${NAMESPACE}" || true

ISTIO_MANIFEST="${ROOT_DIR}/generated/istio.yaml"
if [[ -f "${ISTIO_MANIFEST}" ]]; then
  kubectl delete -f "${ISTIO_MANIFEST}" --ignore-not-found=true
fi

if is_true "${DELETE_NAMESPACE:-false}"; then
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true
fi

echo "Undeploy completed."
