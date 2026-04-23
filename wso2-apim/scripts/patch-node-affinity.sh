#!/usr/bin/env bash
# Inject nodeAffinity into all APIM chart deployment templates to prevent scheduling
# on the RKE2 control-plane (server) node. Pods will only run on agent nodes.
#
# The charts hardcode an affinity: block with podAntiAffinity only; there is no
# values-based override for nodeAffinity. This script runs after pull-charts.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"

ACP_DEPLOYMENT_1="${CHART_CACHE_DIR}/wso2am-acp/templates/control-plane/instance-1/wso2am-cp-deployment.yaml"
ACP_DEPLOYMENT_2="${CHART_CACHE_DIR}/wso2am-acp/templates/control-plane/instance-2/wso2am-cp-deployment.yaml"
TM_DEPLOYMENT_1="${CHART_CACHE_DIR}/wso2am-tm/templates/traffic-manager/instance-1/wso2am-tm-deployment.yaml"
TM_DEPLOYMENT_2="${CHART_CACHE_DIR}/wso2am-tm/templates/traffic-manager/instance-2/wso2am-tm-deployment.yaml"
GW_DEPLOYMENT="${CHART_CACHE_DIR}/wso2am-universal-gw/templates/gateway/wso2am-gateway-deployment.yaml"

for f in "${ACP_DEPLOYMENT_1}" "${ACP_DEPLOYMENT_2}" \
          "${TM_DEPLOYMENT_1}" "${TM_DEPLOYMENT_2}" \
          "${GW_DEPLOYMENT}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Expected chart template not found: ${f}" >&2
    exit 1
  fi
done

# Prepend nodeAffinity (agent-only) to the existing podAntiAffinity block.
# The control-plane label (node-role.kubernetes.io/control-plane) is present only
# on the RKE2 server node; agent nodes lack it, so DoesNotExist targets them.
NODE_AFFINITY_INSERTION='        nodeAffinity:\n          requiredDuringSchedulingIgnoredDuringExecution:\n            nodeSelectorTerms:\n            - matchExpressions:\n              - key: node-role.kubernetes.io\/control-plane\n                operator: DoesNotExist'

for f in "${ACP_DEPLOYMENT_1}" "${ACP_DEPLOYMENT_2}" \
          "${TM_DEPLOYMENT_1}" "${TM_DEPLOYMENT_2}" \
          "${GW_DEPLOYMENT}"; do
  sed -i "s/^      affinity:\$/      affinity:\n${NODE_AFFINITY_INSERTION}/" "${f}"
done

echo "Patched chart deployment templates with agent-node affinity."
