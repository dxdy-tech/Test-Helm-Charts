#!/usr/bin/env bash
# Inject nodeAffinity into all WSO2-MI chart deployment templates to prevent scheduling
# on the RKE2 control-plane (server) node. Pods will only run on agent nodes.
#
# The charts hardcode an affinity: block with podAntiAffinity only; there is no
# values-based override for nodeAffinity. This script runs after pull-charts.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"

MI_DEPLOYMENT="${CHART_CACHE_DIR}/helm-mi/mi/templates/mi-deployment.yaml"
ICP_DEPLOYMENT="${CHART_CACHE_DIR}/helm-mi/icp/templates/icp-deployment.yaml"

for f in "${MI_DEPLOYMENT}" "${ICP_DEPLOYMENT}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Expected chart template not found: ${f}" >&2
    exit 1
  fi
done

# Prepend nodeAffinity (agent-only) to the existing podAntiAffinity block.
# The control-plane label (node-role.kubernetes.io/control-plane) is present only
# on the RKE2 server node; agent nodes lack it, so DoesNotExist targets them.
NODE_AFFINITY_INSERTION='        nodeAffinity:\n          requiredDuringSchedulingIgnoredDuringExecution:\n            nodeSelectorTerms:\n            - matchExpressions:\n              - key: node-role.kubernetes.io\/control-plane\n                operator: DoesNotExist'

for f in "${MI_DEPLOYMENT}" "${ICP_DEPLOYMENT}"; do
  sed -i "s/^      affinity:\$/      affinity:\n${NODE_AFFINITY_INSERTION}/" "${f}"
done

echo "Patched chart deployment templates with agent-node affinity."
