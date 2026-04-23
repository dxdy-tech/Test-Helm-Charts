#!/usr/bin/env bash
# Inject [[internal_apis.users]] into the pulled MI deployment.toml template so
# the file user store has an admin user when file_user_store.enable = true.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MI_DEPLOYMENT_TOML="${ROOT_DIR}/generated/charts/helm-mi/mi/confs/deployment.toml"

if [[ ! -f "${MI_DEPLOYMENT_TOML}" ]]; then
  echo "Expected MI deployment.toml template not found: ${MI_DEPLOYMENT_TOML}" >&2
  exit 1
fi

if grep -q '^\[\[internal_apis.users\]\]' "${MI_DEPLOYMENT_TOML}"; then
  echo "MI deployment.toml already has [[internal_apis.users]] block."
  exit 0
fi

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

awk '
BEGIN { in_file_user_store = 0; inserted = 0 }
$0 == "[internal_apis.file_user_store]" { in_file_user_store = 1 }
in_file_user_store && /^enable = / && inserted == 0 {
  print
  print ""
  print "[[internal_apis.users]]"
  print "user.name = {{ .Values.wso2.config.admin.username | quote }}"
  print "user.password = {{ .Values.wso2.config.admin.password | quote }}"
  print "user.is_admin = true"
  in_file_user_store = 0
  inserted = 1
  next
}
{ print }
END {
  if (inserted == 0) {
    exit 1
  }
}
' "${MI_DEPLOYMENT_TOML}" > "${tmp_file}" || {
  echo "Failed to patch [[internal_apis.users]] into ${MI_DEPLOYMENT_TOML}" >&2
  exit 1
}

mv "${tmp_file}" "${MI_DEPLOYMENT_TOML}"
echo "Patched MI deployment.toml with [[internal_apis.users]] block."
