#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"

DEPLOYMENT_TEMPLATE="${ROOT_DIR}/generated/charts/helm-mi/mi/templates/mi-deployment.yaml"

if [[ ! -f "${DEPLOYMENT_TEMPLATE}" ]]; then
  echo "MI deployment template not found at ${DEPLOYMENT_TEMPLATE}." >&2
  exit 1
fi

# The 4.5.0.16 MI image deploys the sample correctly with its built-in log4j2 config,
# but the chart-provided log4j2 override triggers a Log4J2 parser failure and prevents
# Carbon apps from activating. Keep the deployment.toml override, but stop mounting the
# chart log4j2.properties so the runtime uses the image default.
sed -i '/checksum\.mi\.log4j2\.properties:/d' "${DEPLOYMENT_TEMPLATE}"
sed -i '/^[[:space:]]*- name: wso2mi-log4j2-properties$/,+2d' "${DEPLOYMENT_TEMPLATE}"

echo "Patched MI deployment template to use the image-default log4j2.properties."
