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
  MI_IMAGE_REPOSITORY MI_IMAGE_TAG \
  CUSTOM_IMAGE_REGISTRY MI_CUSTOM_IMAGE_REPOSITORY \
  CUSTOM_IMAGE_PULL_SECRET_USERNAME CUSTOM_IMAGE_PULL_SECRET_PASSWORD

if [[ "${IMAGE_REGISTRY}" != "docker.wso2.com" ]]; then
  echo "Subscription images are required for MI image builds. Set IMAGE_REGISTRY=docker.wso2.com." >&2
  exit 1
fi

trap 'docker logout "${IMAGE_REGISTRY}" >/dev/null 2>&1 || true
      docker logout "${CUSTOM_IMAGE_REGISTRY}" >/dev/null 2>&1 || true' EXIT

echo "Logging in to ${IMAGE_REGISTRY} (WSO2 subscription registry)..."
echo "${IMAGE_PULL_SECRET_PASSWORD}" | docker login "${IMAGE_REGISTRY}" \
  --username "${IMAGE_PULL_SECRET_USERNAME}" --password-stdin

echo "Logging in to ${CUSTOM_IMAGE_REGISTRY} (custom image registry)..."
echo "${CUSTOM_IMAGE_PULL_SECRET_PASSWORD}" | docker login "${CUSTOM_IMAGE_REGISTRY}" \
  --username "${CUSTOM_IMAGE_PULL_SECRET_USERNAME}" --password-stdin

SOURCE_IMAGE="${IMAGE_REGISTRY}/${MI_IMAGE_REPOSITORY}:${MI_IMAGE_TAG}"
TARGET_IMAGE="${CUSTOM_IMAGE_REGISTRY}/${MI_CUSTOM_IMAGE_REPOSITORY}:${MI_IMAGE_TAG}"

echo ""
echo "Building ${TARGET_IMAGE} from ${SOURCE_IMAGE}..."
docker build \
  --build-arg "BASE_IMAGE=${SOURCE_IMAGE}" \
  -f "${ROOT_DIR}/docker/mi.Dockerfile" \
  -t "${TARGET_IMAGE}" \
  "${ROOT_DIR}/docker"

echo "Pushing ${TARGET_IMAGE}..."
docker push "${TARGET_IMAGE}"

echo ""
echo "Custom MI image built and pushed successfully: ${TARGET_IMAGE}"