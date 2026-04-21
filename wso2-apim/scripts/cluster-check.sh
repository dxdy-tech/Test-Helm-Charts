#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_commands kubectl

kubectl config current-context
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || echo "Namespace ${NAMESPACE} does not exist yet (this is fine before first deploy)."
kubectl get nodes -o wide
