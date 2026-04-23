#!/usr/bin/env bash
# Download, build, and stage the official currency converter sample CAR so the
# custom MI image includes it on every deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ENV_FILE="${1:-${ROOT_DIR}/.env}"
load_env_file "${ENV_FILE}"

SAMPLE_URL="https://raw.githubusercontent.com/wso2/docs-mi/main/en/docs/assets/attachments/install-and-setup/currencyconverter.zip"
SAMPLE_ARTIFACT_GLOB='*currency*converter*.car'
CARBONAPPS_DIR="${ROOT_DIR}/docker/carbonapps"
WORK_DIR="${ROOT_DIR}/generated/samples/currencyconverter"
ZIP_PATH="${WORK_DIR}/currencyconverter.zip"
SRC_DIR="${WORK_DIR}/src"
PROJECT_DIR="${SRC_DIR}/currencyconverter"
LOCAL_ENTRY_PATH="${PROJECT_DIR}/src/main/wso2mi/artifacts/local-entries/CurrencyConverter.xml"

require_commands curl java python3
require_vars CURRENCY_SERVICE_URL

case "${CURRENCY_SERVICE_URL}" in
  http://*)
    connection_type="HTTP"
    ;;
  https://*)
    connection_type="HTTPS"
    ;;
  *)
    echo "CURRENCY_SERVICE_URL must start with http:// or https://: ${CURRENCY_SERVICE_URL}" >&2
    exit 1
    ;;
esac

mkdir -p "${CARBONAPPS_DIR}" "${WORK_DIR}"

echo "Downloading currency converter sample project..."
curl -L --fail --show-error --silent -o "${ZIP_PATH}" "${SAMPLE_URL}"

rm -rf "${SRC_DIR}"
python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "${ZIP_PATH}" "${SRC_DIR}"

if [[ ! -f "${PROJECT_DIR}/mvnw" ]]; then
  echo "Expected Maven Wrapper not found in ${PROJECT_DIR}." >&2
  exit 1
fi

chmod +x "${PROJECT_DIR}/mvnw"

echo "Configuring currency converter sample for ${connection_type} backend URLs..."
python3 - "${LOCAL_ENTRY_PATH}" "${connection_type}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
connection_type = sys.argv[2]
text = path.read_text()
start_tag = "<connectionType>"
end_tag = "</connectionType>"
start = text.find(start_tag)
end = text.find(end_tag, start)
if start == -1 or end == -1:
    raise SystemExit(f"Could not find connectionType in {path}")
end += len(end_tag)
updated = text[:start] + f"<connectionType>{connection_type}</connectionType>" + text[end:]
path.write_text(updated)
PY

echo "Building currency converter sample CAR..."
(
  cd "${PROJECT_DIR}"
  ./mvnw -q clean install -Dmaven.test.skip=true
)

sample_car="$(find "${PROJECT_DIR}/target" -maxdepth 1 -type f -name '*.car' | head -n 1 || true)"
if [[ -z "${sample_car}" ]]; then
  echo "Currency converter sample build did not produce a CAR artifact." >&2
  exit 1
fi

find "${CARBONAPPS_DIR}" -maxdepth 1 -type f -iname "${SAMPLE_ARTIFACT_GLOB}" -delete
cp "${sample_car}" "${CARBONAPPS_DIR}/"

echo "Staged $(basename "${sample_car}") in ${CARBONAPPS_DIR}."
