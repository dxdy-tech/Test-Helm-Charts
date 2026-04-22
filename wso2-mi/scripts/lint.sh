#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
require_commands helm envsubst git
require_vars HELM_MI_CHART_REF

bash "${SCRIPT_DIR}/render-values.sh" "${ENV_FILE}"
bash "${SCRIPT_DIR}/pull-charts.sh" "${ENV_FILE}"

CHART_DIR="${ROOT_DIR}/generated/charts/helm-mi/mi"
helm lint "${CHART_DIR}" -f "${ROOT_DIR}/generated/mi-values.yaml"

echo "Helm lint completed."
