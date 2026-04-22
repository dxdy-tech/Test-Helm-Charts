#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
require_commands git
require_vars HELM_MI_CHART_REPO HELM_MI_CHART_REF

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"
REPO_DIR="${CHART_CACHE_DIR}/helm-mi"

rm -rf "${CHART_CACHE_DIR}"
mkdir -p "${CHART_CACHE_DIR}"

if ! git clone --depth 1 --branch "${HELM_MI_CHART_REF}" "${HELM_MI_CHART_REPO}" "${REPO_DIR}"; then
  echo "Branch clone failed for ref ${HELM_MI_CHART_REF}; retrying with default clone and checkout."
  git clone --depth 1 "${HELM_MI_CHART_REPO}" "${REPO_DIR}"
  git -C "${REPO_DIR}" fetch --depth 1 origin "${HELM_MI_CHART_REF}" || true
  git -C "${REPO_DIR}" checkout "${HELM_MI_CHART_REF}"
fi

if [[ ! -d "${REPO_DIR}/mi" ]]; then
  echo "MI chart path not found at ${REPO_DIR}/mi" >&2
  exit 1
fi

if [[ ! -d "${REPO_DIR}/icp" ]]; then
  echo "ICP chart path not found at ${REPO_DIR}/icp" >&2
  exit 1
fi

echo "Pulled helm-mi charts to ${CHART_CACHE_DIR}."
