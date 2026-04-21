#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
require_commands docker
require_vars \
  IMAGE_REGISTRY IMAGE_PULL_SECRET_USERNAME IMAGE_PULL_SECRET_PASSWORD \
  ACP_IMAGE_REPOSITORY TM_IMAGE_REPOSITORY GW_IMAGE_REPOSITORY \
  ACP_IMAGE_TAG TM_IMAGE_TAG GW_IMAGE_TAG \
  CUSTOM_IMAGE_REGISTRY \
  ACP_CUSTOM_IMAGE_REPOSITORY TM_CUSTOM_IMAGE_REPOSITORY GW_CUSTOM_IMAGE_REPOSITORY \
  CUSTOM_IMAGE_PULL_SECRET_USERNAME CUSTOM_IMAGE_PULL_SECRET_PASSWORD \
  POSTGRES_JDBC_VERSION

trap 'docker logout "${IMAGE_REGISTRY}" >/dev/null 2>&1 || true
      docker logout "${CUSTOM_IMAGE_REGISTRY}" >/dev/null 2>&1 || true' EXIT

echo "Logging in to ${IMAGE_REGISTRY} (WSO2 subscription registry)..."
echo "${IMAGE_PULL_SECRET_PASSWORD}" | docker login "${IMAGE_REGISTRY}" \
  --username "${IMAGE_PULL_SECRET_USERNAME}" --password-stdin

echo "Logging in to ${CUSTOM_IMAGE_REGISTRY} (custom image registry)..."
echo "${CUSTOM_IMAGE_PULL_SECRET_PASSWORD}" | docker login "${CUSTOM_IMAGE_REGISTRY}" \
  --username "${CUSTOM_IMAGE_PULL_SECRET_USERNAME}" --password-stdin

build_and_push() {
  local source_repo="${1}"   # e.g., wso2am-acp
  local source_tag="${2}"    # e.g., 4.6.0.23-alpine
  local target_repo="${3}"   # e.g., vsoneworld/openg2pdad-wso2-apim-acp
  local dockerfile="${4}"    # relative path, e.g., docker/acp.Dockerfile

  local source_image="${IMAGE_REGISTRY}/${source_repo}:${source_tag}"
  local target_image="${CUSTOM_IMAGE_REGISTRY}/${target_repo}:${source_tag}"

  echo ""
  echo "Building ${target_image} from ${source_image}..."
  docker build \
    --build-arg "BASE_IMAGE=${source_image}" \
    --build-arg "POSTGRES_JDBC_VERSION=${POSTGRES_JDBC_VERSION}" \
    -f "${ROOT_DIR}/${dockerfile}" \
    -t "${target_image}" \
    "${ROOT_DIR}/docker"

  echo "Pushing ${target_image}..."
  docker push "${target_image}"
  echo "Pushed ${target_image}."
}

build_and_push "${ACP_IMAGE_REPOSITORY}" "${ACP_IMAGE_TAG}" "${ACP_CUSTOM_IMAGE_REPOSITORY}" "docker/acp.Dockerfile"
build_and_push "${TM_IMAGE_REPOSITORY}"  "${TM_IMAGE_TAG}"  "${TM_CUSTOM_IMAGE_REPOSITORY}"  "docker/tm.Dockerfile"
build_and_push "${GW_IMAGE_REPOSITORY}"  "${GW_IMAGE_TAG}"  "${GW_CUSTOM_IMAGE_REPOSITORY}"  "docker/gw.Dockerfile"

echo ""
echo "All custom images built and pushed successfully."
