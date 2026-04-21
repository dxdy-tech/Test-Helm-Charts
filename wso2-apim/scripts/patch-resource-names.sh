#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"

ACP_DEPLOYMENT_1="${CHART_CACHE_DIR}/wso2am-acp/templates/control-plane/instance-1/wso2am-cp-deployment.yaml"
ACP_DEPLOYMENT_2="${CHART_CACHE_DIR}/wso2am-acp/templates/control-plane/instance-2/wso2am-cp-deployment.yaml"
TM_DEPLOYMENT_1="${CHART_CACHE_DIR}/wso2am-tm/templates/traffic-manager/instance-1/wso2am-tm-deployment.yaml"
TM_DEPLOYMENT_2="${CHART_CACHE_DIR}/wso2am-tm/templates/traffic-manager/instance-2/wso2am-tm-deployment.yaml"
GW_DEPLOYMENT="${CHART_CACHE_DIR}/wso2am-universal-gw/templates/gateway/wso2am-gateway-deployment.yaml"
GW_HPA="${CHART_CACHE_DIR}/wso2am-universal-gw/templates/gateway/wso2am-gateway-hpa.yaml"

for f in "${ACP_DEPLOYMENT_1}" "${ACP_DEPLOYMENT_2}" "${TM_DEPLOYMENT_1}" "${TM_DEPLOYMENT_2}" "${GW_DEPLOYMENT}" "${GW_HPA}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Expected chart template not found: ${f}" >&2
    exit 1
  fi
done

perl -0pi -e 's/\Q{{ template "apim-helm-cp.fullname" . }}-deployment-1\E/{{ template "apim-helm-cp.fullname" . }}-1/g' "${ACP_DEPLOYMENT_1}"
perl -0pi -e 's/\Q{{ template "apim-helm-cp.fullname" . }}-deployment-2\E/{{ template "apim-helm-cp.fullname" . }}-2/g' "${ACP_DEPLOYMENT_2}"
perl -0pi -e 's/\Q{{ template "apim-helm-tm.fullname" . }}-deployment-1\E/{{ template "apim-helm-tm.fullname" . }}-1/g' "${TM_DEPLOYMENT_1}"
perl -0pi -e 's/\Q{{ template "apim-helm-tm.fullname" . }}-deployment-2\E/{{ template "apim-helm-tm.fullname" . }}-2/g' "${TM_DEPLOYMENT_2}"
perl -0pi -e 's/\Q{{ template "apim-helm-gw.fullname" . }}-deployment\E/{{ template "apim-helm-gw.fullname" . }}/g' "${GW_DEPLOYMENT}"
perl -0pi -e 's/\Q{{ template "apim-helm-gw.fullname" . }}-deployment\E/{{ template "apim-helm-gw.fullname" . }}/g' "${GW_HPA}"

# WSO2 private registry digests may differ from Docker Hub digests.
# Force chart templates to use image tags to avoid digest mismatch pull errors.
IMAGE_REF_DIGEST='{{ .Values.wso2.deployment.image.repository }}@{{ .Values.wso2.deployment.image.digest }}'
IMAGE_REF_TAG='{{ .Values.wso2.deployment.image.repository }}:{{ .Values.wso2.deployment.image.tag }}'

for f in "${ACP_DEPLOYMENT_1}" "${ACP_DEPLOYMENT_2}" "${TM_DEPLOYMENT_1}" "${TM_DEPLOYMENT_2}" "${GW_DEPLOYMENT}"; do
  sed -i "s|${IMAGE_REF_DIGEST}|${IMAGE_REF_TAG}|g" "${f}"
done

echo "Patched chart templates with fixed deployment names and tag-based image references."
