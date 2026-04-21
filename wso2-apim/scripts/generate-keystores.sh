#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"
require_commands keytool
require_vars KEYSTORE_PASSWORD KEYSTORE_KEY_PASSWORD KEYSTORE_DNAME

KEYSTORE_DIR="${ROOT_DIR}/generated/keystores"
PRIMARY_KEYSTORE="${KEYSTORE_DIR}/wso2carbon.jks"
TRUSTSTORE="${KEYSTORE_DIR}/client-truststore.jks"
CERT_FILE="${KEYSTORE_DIR}/wso2carbon.crt"

mkdir -p "${KEYSTORE_DIR}"

if [[ -f "${PRIMARY_KEYSTORE}" && -f "${TRUSTSTORE}" && "${FORCE_KEYSTORE_REGEN:-false}" != "true" ]]; then
  echo "Keystores already exist at ${KEYSTORE_DIR}; skipping regeneration."
  exit 0
fi

rm -f "${PRIMARY_KEYSTORE}" "${TRUSTSTORE}" "${CERT_FILE}"

keytool -genkeypair \
  -alias wso2carbon \
  -keyalg RSA \
  -keysize 2048 \
  -validity 3650 \
  -dname "${KEYSTORE_DNAME}" \
  -keystore "${PRIMARY_KEYSTORE}" \
  -storetype JKS \
  -storepass "${KEYSTORE_PASSWORD}" \
  -keypass "${KEYSTORE_KEY_PASSWORD}" \
  -noprompt

keytool -exportcert \
  -alias wso2carbon \
  -keystore "${PRIMARY_KEYSTORE}" \
  -storepass "${KEYSTORE_PASSWORD}" \
  -rfc \
  -file "${CERT_FILE}"

keytool -importcert \
  -alias wso2carbon \
  -file "${CERT_FILE}" \
  -keystore "${TRUSTSTORE}" \
  -storetype JKS \
  -storepass "${KEYSTORE_PASSWORD}" \
  -noprompt

rm -f "${CERT_FILE}"

echo "Generated ${PRIMARY_KEYSTORE} and ${TRUSTSTORE}"
