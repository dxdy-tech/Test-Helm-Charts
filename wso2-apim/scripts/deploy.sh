#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_commands helm kubectl envsubst
require_vars \
  NAMESPACE WSO2_CHART_VERSION \
  ACP_RELEASE_NAME TM_RELEASE_NAME GW_RELEASE_NAME \
  HELM_TIMEOUT HELM_WAIT HELM_ATOMIC \
  DB_HOST DB_PORT DB_USERNAME DB_PASSWORD APIM_DB_NAME SHARED_DB_NAME \
  IMAGE_REGISTRY

validate_image_registry_config() {
  # WSO2 subscription registry — used for pulling base images during Docker build
  if [[ "${IMAGE_REGISTRY}" != "docker.wso2.com" ]]; then
    echo "Subscription images are required. Set IMAGE_REGISTRY=docker.wso2.com." >&2
    exit 1
  fi

  require_vars IMAGE_PULL_SECRET_USERNAME IMAGE_PULL_SECRET_PASSWORD

  if [[ "${IMAGE_PULL_SECRET_USERNAME}" == REPLACE_WITH_* || "${IMAGE_PULL_SECRET_PASSWORD}" == REPLACE_WITH_* ]]; then
    echo "Set IMAGE_PULL_SECRET_USERNAME and IMAGE_PULL_SECRET_PASSWORD (WSO2 credentials) in ${ENV_FILE} before deployment." >&2
    exit 1
  fi

  # Custom registry — where built images are pushed and pods pull from
  require_vars CUSTOM_IMAGE_REGISTRY CUSTOM_IMAGE_PULL_SECRET_USERNAME CUSTOM_IMAGE_PULL_SECRET_PASSWORD

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

"${SCRIPT_DIR}/create-secrets.sh" "${ENV_FILE}"

release_present=false
for release_name in "${ACP_RELEASE_NAME}" "${TM_RELEASE_NAME}" "${GW_RELEASE_NAME}"; do
  if helm status "${release_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    release_present=true
    break
  fi
done

schema_ready=false
set +e
bash "${SCRIPT_DIR}/check-schema.sh" "${ENV_FILE}"
schema_check_status=$?
set -e

if [[ "${schema_check_status}" -eq 0 ]]; then
  schema_ready=true
elif [[ "${schema_check_status}" -eq 10 ]]; then
  schema_ready=false
else
  echo "Schema readiness check failed with exit code ${schema_check_status}." >&2
  exit "${schema_check_status}"
fi

if [[ "${release_present}" == "false" && "${schema_ready}" == "false" ]]; then
  echo "First-time install detected. Preparing databases and bootstrapping WSO2 schema."
  DB_PREPARE_MODE="${DB_PREPARE_MODE:-cluster}" bash "${SCRIPT_DIR}/prepare-postgres.sh" "${ENV_FILE}"
  SCHEMA_APPLY_MODE="${SCHEMA_APPLY_MODE:-${DB_PREPARE_MODE:-cluster}}" bash "${SCRIPT_DIR}/bootstrap-postgres-schema.sh" "${ENV_FILE}"
else
  echo "Skipping DB bootstrap (release_present=${release_present}, schema_ready=${schema_ready})."
fi

"${SCRIPT_DIR}/render-values.sh" "${ENV_FILE}"
"${SCRIPT_DIR}/pull-charts.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/patch-resource-names.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/patch-key-manager-config.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/patch-node-affinity.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/patch-log4j2.sh" "${ENV_FILE}"

# Render and apply Istio Gateway + VirtualServices
require_vars ISTIO_GATEWAY_NAME
mkdir -p "${ROOT_DIR}/generated"
envsubst < "${ROOT_DIR}/manifests/istio.yaml.tmpl" > "${ROOT_DIR}/generated/istio.yaml"
kubectl apply -f "${ROOT_DIR}/generated/istio.yaml"

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"

# The log4j2 patch runs after chart extraction and writes the ConfigMap data
# with kubectl-client ownership. On Helm upgrades that conflicts with Helm SSA.
# Pre-delete so Helm recreates them cleanly on every upgrade.
kubectl -n "${NAMESPACE}" delete configmap \
  openg2p-wso2-apim-control-plane-conf-log4j2 \
  openg2p-wso2-apim-traffic-manager-conf-log4j2 \
  openg2p-wso2-apim-gateway-conf-log4j2 \
  --ignore-not-found 2>/dev/null || true

HELM_FLAGS=(--namespace "${NAMESPACE}" --create-namespace --force-conflicts)
if is_true "${HELM_WAIT}"; then
  HELM_FLAGS+=(--wait --timeout "${HELM_TIMEOUT}")
fi
if is_true "${HELM_ATOMIC}"; then
  HELM_FLAGS+=(--rollback-on-failure)
fi

helm upgrade --install "${ACP_RELEASE_NAME}" "${CHART_CACHE_DIR}/wso2am-acp" -f "${ROOT_DIR}/generated/acp-values.yaml" "${HELM_FLAGS[@]}"
helm upgrade --install "${TM_RELEASE_NAME}" "${CHART_CACHE_DIR}/wso2am-tm" -f "${ROOT_DIR}/generated/tm-values.yaml" "${HELM_FLAGS[@]}"
helm upgrade --install "${GW_RELEASE_NAME}" "${CHART_CACHE_DIR}/wso2am-universal-gw" -f "${ROOT_DIR}/generated/gw-values.yaml" "${HELM_FLAGS[@]}"

kubectl -n "${NAMESPACE}" get pods
kubectl -n "${NAMESPACE}" get svc
kubectl -n "${NAMESPACE}" get ing || true
kubectl -n "${NAMESPACE}" get virtualservice || true

echo "Deployment completed."
