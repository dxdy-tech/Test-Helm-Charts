#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_commands kubectl
require_vars NAMESPACE KEYSTORE_SECRET_NAME

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${CUSTOM_IMAGE_REGISTRY:-}" ]]; then
  require_vars IMAGE_PULL_SECRET_NAME CUSTOM_IMAGE_PULL_SECRET_USERNAME CUSTOM_IMAGE_PULL_SECRET_PASSWORD
  kubectl -n "${NAMESPACE}" create secret docker-registry "${IMAGE_PULL_SECRET_NAME}" \
    --docker-server="${CUSTOM_IMAGE_REGISTRY}" \
    --docker-username="${CUSTOM_IMAGE_PULL_SECRET_USERNAME}" \
    --docker-password="${CUSTOM_IMAGE_PULL_SECRET_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl -n "${NAMESPACE}" patch serviceaccount default --type merge \
    -p "{\"imagePullSecrets\":[{\"name\":\"${IMAGE_PULL_SECRET_NAME}\"}]}" >/dev/null

  echo "Applied image pull secret ${IMAGE_PULL_SECRET_NAME} for ${CUSTOM_IMAGE_REGISTRY} and patched default ServiceAccount in namespace ${NAMESPACE}."
else
  echo "CUSTOM_IMAGE_REGISTRY is empty; skipping image pull secret creation."
fi

# WSO2 subscription pull secret — required for ICP to pull from docker.wso2.com.
if [[ -n "${IMAGE_REGISTRY:-}" && -n "${WSO2_IMAGE_PULL_SECRET_NAME:-}" ]]; then
  require_vars IMAGE_PULL_SECRET_USERNAME IMAGE_PULL_SECRET_PASSWORD
  kubectl -n "${NAMESPACE}" create secret docker-registry "${WSO2_IMAGE_PULL_SECRET_NAME}" \
    --docker-server="${IMAGE_REGISTRY}" \
    --docker-username="${IMAGE_PULL_SECRET_USERNAME}" \
    --docker-password="${IMAGE_PULL_SECRET_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "Applied WSO2 subscription pull secret ${WSO2_IMAGE_PULL_SECRET_NAME} for ${IMAGE_REGISTRY} in namespace ${NAMESPACE}."
fi

if is_true "${AUTO_GENERATE_KEYSTORES:-false}"; then
  bash "${SCRIPT_DIR}/generate-keystores.sh" "${ENV_FILE}"
fi

KEYSTORE_DIR="${ROOT_DIR}/generated/keystores"
PRIMARY_KEYSTORE="${KEYSTORE_DIR}/wso2carbon.jks"
INTERNAL_KEYSTORE="${KEYSTORE_DIR}/wso2internal.jks"
TRUSTSTORE="${KEYSTORE_DIR}/client-truststore.jks"

if [[ -f "${PRIMARY_KEYSTORE}" && -f "${INTERNAL_KEYSTORE}" && -f "${TRUSTSTORE}" ]]; then
  kubectl -n "${NAMESPACE}" create secret generic "${KEYSTORE_SECRET_NAME}" \
    --from-file=wso2carbon.jks="${PRIMARY_KEYSTORE}" \
    --from-file=wso2internal.jks="${INTERNAL_KEYSTORE}" \
    --from-file=client-truststore.jks="${TRUSTSTORE}" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "Applied keystore secret ${KEYSTORE_SECRET_NAME} in namespace ${NAMESPACE}."
elif kubectl -n "${NAMESPACE}" get secret "${KEYSTORE_SECRET_NAME}" >/dev/null 2>&1; then
  echo "Keystore files were not found, but existing secret ${KEYSTORE_SECRET_NAME} is present; continuing."
else
  echo "Keystore files are missing and secret ${KEYSTORE_SECRET_NAME} does not exist." >&2
  echo "Set AUTO_GENERATE_KEYSTORES=true or create the secret manually before deploy." >&2
  exit 1
fi

echo "Secrets are ready in namespace ${NAMESPACE}."
