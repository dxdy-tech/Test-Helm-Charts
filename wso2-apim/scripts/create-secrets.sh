#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
ensure_kubeconfig_default
require_commands kubectl
require_vars NAMESPACE DB_SECRET_NAME DB_USERNAME DB_PASSWORD DB_HOST DB_PORT KEYSTORE_SECRET_NAME \
  CUSTOM_IMAGE_REGISTRY CUSTOM_IMAGE_PULL_SECRET_USERNAME CUSTOM_IMAGE_PULL_SECRET_PASSWORD \
  ADMIN_SECRET_NAME

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic "${DB_SECRET_NAME}" \
  --from-literal=username="${DB_USERNAME}" \
  --from-literal=password="${DB_PASSWORD}" \
  --from-literal=host="${DB_HOST}" \
  --from-literal=port="${DB_PORT}" \
  --dry-run=client -o yaml | kubectl apply -f -

IMAGE_PULL_SECRET_NAME="${IMAGE_PULL_SECRET_NAME:-apim-registry-auth}"
kubectl -n "${NAMESPACE}" create secret docker-registry "${IMAGE_PULL_SECRET_NAME}" \
  --docker-server="${CUSTOM_IMAGE_REGISTRY}" \
  --docker-username="${CUSTOM_IMAGE_PULL_SECRET_USERNAME}" \
  --docker-password="${CUSTOM_IMAGE_PULL_SECRET_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${NAMESPACE}" patch serviceaccount default --type merge \
  -p "{\"imagePullSecrets\":[{\"name\":\"${IMAGE_PULL_SECRET_NAME}\"}]}" >/dev/null
echo "Applied shared image pull secret ${IMAGE_PULL_SECRET_NAME} and patched default ServiceAccount in namespace ${NAMESPACE}."

if is_true "${AUTO_GENERATE_KEYSTORES:-false}"; then
  "${SCRIPT_DIR}/generate-keystores.sh" "${ENV_FILE}"
fi

KEYSTORE_DIR="${ROOT_DIR}/generated/keystores"
PRIMARY_KEYSTORE="${KEYSTORE_DIR}/wso2carbon.jks"
TRUSTSTORE="${KEYSTORE_DIR}/client-truststore.jks"

if [[ -f "${PRIMARY_KEYSTORE}" && -f "${TRUSTSTORE}" ]]; then
  kubectl -n "${NAMESPACE}" create secret generic "${KEYSTORE_SECRET_NAME}" \
    --from-file=wso2carbon.jks="${PRIMARY_KEYSTORE}" \
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

# ── Admin credentials secret ─────────────────────────────────────────────────
# The secret must be pre-created by the operator with 'username' and 'password' keys.
# Example:
#   kubectl -n "${NAMESPACE}" create secret generic "${ADMIN_SECRET_NAME}" \
#     --from-literal=username=admin \
#     --from-literal=password=<strong-password>
if ! kubectl -n "${NAMESPACE}" get secret "${ADMIN_SECRET_NAME}" >/dev/null 2>&1; then
  echo "ERROR: Admin credentials secret '${ADMIN_SECRET_NAME}' not found in namespace '${NAMESPACE}'." >&2
  echo "Create it manually before running deploy:" >&2
  echo "  kubectl -n ${NAMESPACE} create secret generic ${ADMIN_SECRET_NAME} \\" >&2
  echo "    --from-literal=username=<username> \\" >&2
  echo "    --from-literal=password=<password>" >&2
  exit 1
fi
echo "Admin credentials secret ${ADMIN_SECRET_NAME} is present in namespace ${NAMESPACE}."

echo "Secrets are ready in namespace ${NAMESPACE}."
