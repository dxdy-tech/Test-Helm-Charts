#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

load_env_file() {
  local env_file="${1:-${ROOT_DIR}/.env}"
  if [[ ! -f "${env_file}" ]]; then
    echo "Env file not found: ${env_file}" >&2
    echo "Copy .env.example to .env and adjust values." >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}

require_commands() {
  local missing=0
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "Required command not found: ${cmd}" >&2
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi
}

require_vars() {
  local missing=0
  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      echo "Required variable is empty: ${var_name}" >&2
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi
}

ensure_kubeconfig_default() {
  export KUBECONFIG="${KUBECONFIG:-/home/chamath/Downloads/openg2p-dad.yaml}"
}

is_true() {
  local value="${1:-false}"
  [[ "${value,,}" == "true" ]]
}
