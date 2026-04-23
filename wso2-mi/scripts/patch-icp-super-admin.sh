#!/usr/bin/env bash
# Inject [super_admin] into the pulled ICP deployment.toml template so
# ConfigParser generates user-mgt.xml with deploy-time admin credentials.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ICP_DEPLOYMENT_TOML="${ROOT_DIR}/generated/charts/helm-mi/icp/confs/deployment.toml"

if [[ ! -f "${ICP_DEPLOYMENT_TOML}" ]]; then
  echo "Expected ICP deployment.toml template not found: ${ICP_DEPLOYMENT_TOML}" >&2
  exit 1
fi

if grep -q '^\[super_admin\]' "${ICP_DEPLOYMENT_TOML}" \
  && grep -q '^\[\[internal_apis.users\]\]' "${ICP_DEPLOYMENT_TOML}"; then
  echo "ICP deployment.toml already has [super_admin] and [[internal_apis.users]] blocks."
  exit 0
fi

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

awk '
BEGIN { inserted = 0 }
$0 == "[internal_apis.file_user_store]" && inserted == 0 {
  print "[super_admin]"
  print "username = {{ .Values.wso2.config.admin.username | quote }}"
  print "password = {{ .Values.wso2.config.admin.password | quote }}"
  print ""
  print "[[internal_apis.users]]"
  print "user.name = {{ .Values.wso2.config.admin.username | quote }}"
  print "user.password = {{ .Values.wso2.config.admin.password | quote }}"
  print "user.is_admin = true"
  print ""
  inserted = 1
}
{ print }
END {
  if (inserted == 0) {
    exit 1
  }
}
' "${ICP_DEPLOYMENT_TOML}" > "${tmp_file}" || {
  echo "Failed to patch [super_admin] into ${ICP_DEPLOYMENT_TOML}" >&2
  exit 1
}

mv "${tmp_file}" "${ICP_DEPLOYMENT_TOML}"
echo "Patched ICP deployment.toml with [super_admin] and [[internal_apis.users]] blocks."