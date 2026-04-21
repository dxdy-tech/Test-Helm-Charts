#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
require_commands envsubst
require_vars \
  INGRESS_CLASS CONTROL_PLANE_HOSTNAME GW_HOSTNAME WS_HOSTNAME WEBSUB_HOSTNAME \
  DB_HOST DB_PORT DB_USERNAME DB_PASSWORD APIM_DB_NAME SHARED_DB_NAME \
  APIM_ADMIN_USERNAME APIM_ADMIN_PASSWORD KEYSTORE_SECRET_NAME \
  CUSTOM_IMAGE_REGISTRY \
  ACP_CUSTOM_IMAGE_REPOSITORY TM_CUSTOM_IMAGE_REPOSITORY GW_CUSTOM_IMAGE_REPOSITORY \
  ACP_IMAGE_TAG TM_IMAGE_TAG GW_IMAGE_TAG

mkdir -p "${ROOT_DIR}/generated"

envsubst < "${ROOT_DIR}/values/acp-values.yaml.tmpl" > "${ROOT_DIR}/generated/acp-values.yaml"
envsubst < "${ROOT_DIR}/values/tm-values.yaml.tmpl" > "${ROOT_DIR}/generated/tm-values.yaml"
envsubst < "${ROOT_DIR}/values/gw-values.yaml.tmpl" > "${ROOT_DIR}/generated/gw-values.yaml"

echo "Rendered values files under ${ROOT_DIR}/generated"
