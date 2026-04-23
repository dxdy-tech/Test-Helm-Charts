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
  APIM_ADMIN_USERNAME ADMIN_SECRET_NAME KEYSTORE_SECRET_NAME \
  CUSTOM_IMAGE_REGISTRY \
  ACP_CUSTOM_IMAGE_REPOSITORY TM_CUSTOM_IMAGE_REPOSITORY GW_CUSTOM_IMAGE_REPOSITORY \
  ACP_IMAGE_TAG TM_IMAGE_TAG GW_IMAGE_TAG \
  ACP_HIGH_AVAILABILITY TM_HIGH_AVAILABILITY

mkdir -p "${ROOT_DIR}/generated"

# Build per-instance JMS URL lists for eventhub/throttling.
# The WSO2 chart creates one Deployment per instance, named <fullname>-<N>-service.
# With highAvailability=true the chart renders instance-1 and instance-2; otherwise only instance-1.
_acp_base="openg2p-wso2-apim-control-plane"
_tm_base="openg2p-wso2-apim-traffic-manager"

# The chart supports exactly 1 instance normally, 2 when highAvailability=true.
_acp_count=1; [[ "${ACP_HIGH_AVAILABILITY}" == "true" ]] && _acp_count=2
_tm_count=1;  [[ "${TM_HIGH_AVAILABILITY}"  == "true" ]] && _tm_count=2

export ACP_EVENTHUB_URLS
ACP_EVENTHUB_URLS=$(for i in $(seq 1 "${_acp_count}"); do printf '          - "%s-%s-service"\n' "${_acp_base}" "${i}"; done)
ACP_EVENTHUB_URLS="${ACP_EVENTHUB_URLS%$'\n'}"

export TM_THROTTLE_URLS
TM_THROTTLE_URLS=$(for i in $(seq 1 "${_tm_count}"); do printf '          - "%s-%s-service"\n' "${_tm_base}" "${i}"; done)
TM_THROTTLE_URLS="${TM_THROTTLE_URLS%$'\n'}"

envsubst < "${ROOT_DIR}/values/acp-values.yaml.tmpl" > "${ROOT_DIR}/generated/acp-values.yaml"
envsubst < "${ROOT_DIR}/values/tm-values.yaml.tmpl" > "${ROOT_DIR}/generated/tm-values.yaml"
envsubst < "${ROOT_DIR}/values/gw-values.yaml.tmpl" > "${ROOT_DIR}/generated/gw-values.yaml"

echo "Rendered values files under ${ROOT_DIR}/generated"
