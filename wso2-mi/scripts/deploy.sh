#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_commands helm kubectl envsubst git
require_vars \
  NAMESPACE MI_RELEASE_NAME \
  HELM_TIMEOUT HELM_WAIT HELM_ATOMIC \
  IMAGE_REGISTRY CUSTOM_IMAGE_REGISTRY

validate_image_registry_config() {
  if [[ "${IMAGE_REGISTRY}" != "docker.wso2.com" ]]; then
    echo "Subscription images are required. Set IMAGE_REGISTRY=docker.wso2.com." >&2
    exit 1
  fi

  require_vars IMAGE_PULL_SECRET_USERNAME IMAGE_PULL_SECRET_PASSWORD
  if [[ "${IMAGE_PULL_SECRET_USERNAME}" == REPLACE_WITH_* || "${IMAGE_PULL_SECRET_PASSWORD}" == REPLACE_WITH_* ]]; then
    echo "Set IMAGE_PULL_SECRET_USERNAME and IMAGE_PULL_SECRET_PASSWORD (WSO2 credentials) in ${ENV_FILE} before deployment." >&2
    exit 1
  fi

  require_vars IMAGE_PULL_SECRET_NAME CUSTOM_IMAGE_PULL_SECRET_USERNAME CUSTOM_IMAGE_PULL_SECRET_PASSWORD
  if [[ "${CUSTOM_IMAGE_PULL_SECRET_USERNAME}" == REPLACE_WITH_* || "${CUSTOM_IMAGE_PULL_SECRET_PASSWORD}" == REPLACE_WITH_* ]]; then
    echo "Set CUSTOM_IMAGE_PULL_SECRET_USERNAME and CUSTOM_IMAGE_PULL_SECRET_PASSWORD in ${ENV_FILE} before deployment." >&2
    exit 1
  fi
}

validate_image_registry_config

if ! is_true "${SKIP_IMAGE_BUILD:-false}"; then
  bash "${SCRIPT_DIR}/build-images.sh" "${ENV_FILE}"
else
  echo "Skipping image build (SKIP_IMAGE_BUILD=true)."
fi

bash "${SCRIPT_DIR}/cluster-check.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/create-secrets.sh" "${ENV_FILE}"

bash "${SCRIPT_DIR}/render-values.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/pull-charts.sh" "${ENV_FILE}"

# Render and apply Istio Gateway + VirtualService (MI + ICP)
require_vars ISTIO_GATEWAY_NAME ISTIO_TLS_MODE MI_HTTPS_PORT \
             ICP_ISTIO_GATEWAY_NAME ICP_HOSTNAME ICP_HTTPS_PORT ICP_RELEASE_NAME
mkdir -p "${ROOT_DIR}/generated"
envsubst < "${ROOT_DIR}/manifests/istio.yaml.tmpl" > "${ROOT_DIR}/generated/istio.yaml"
kubectl apply -f "${ROOT_DIR}/generated/istio.yaml"

MI_CHART_DIR="${ROOT_DIR}/generated/charts/helm-mi/mi"
ICP_CHART_DIR="${ROOT_DIR}/generated/charts/helm-mi/icp"

HELM_FLAGS=(--namespace "${NAMESPACE}" --create-namespace)
if is_true "${HELM_WAIT}"; then
  HELM_FLAGS+=(--wait --timeout "${HELM_TIMEOUT}")
fi
if is_true "${HELM_ATOMIC}"; then
  HELM_FLAGS+=(--rollback-on-failure)
fi

# If a release is stuck in pending-install/upgrade state (e.g. previous run was killed),
# helm upgrade --install will refuse to proceed. Detect and recover by uninstalling first.
helm_safe_upgrade() {
  local release="$1"; shift
  local status
  status=$(helm status "${release}" --namespace "${NAMESPACE}" -o json 2>/dev/null \
             | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  if [[ "${status}" == "pending-install" || "${status}" == "pending-upgrade" || "${status}" == "pending-rollback" ]]; then
    echo "Release ${release} is stuck in '${status}' state — uninstalling to recover..."
    helm uninstall "${release}" --namespace "${NAMESPACE}" --no-hooks 2>/dev/null || true
  fi
  helm upgrade --install "${release}" "$@"
}

helm_safe_upgrade "${MI_RELEASE_NAME}"  "${MI_CHART_DIR}"  -f "${ROOT_DIR}/generated/mi-values.yaml"  "${HELM_FLAGS[@]}"
helm_safe_upgrade "${ICP_RELEASE_NAME}" "${ICP_CHART_DIR}" -f "${ROOT_DIR}/generated/icp-values.yaml" "${HELM_FLAGS[@]}"

kubectl -n "${NAMESPACE}" get pods
kubectl -n "${NAMESPACE}" get svc
kubectl -n "${NAMESPACE}" get ing || true
kubectl -n "${NAMESPACE}" get gateway,httproute || true
kubectl -n "${NAMESPACE}" get virtualservice || true

echo "Deployment completed."
