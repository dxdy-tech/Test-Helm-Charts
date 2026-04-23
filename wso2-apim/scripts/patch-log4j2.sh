#!/usr/bin/env bash
# Removes a log4j 1.x-style "category." line that was inadvertently included in
# the WSO2 APIM chart's log4j2.properties files.  Pax-logging (the OSGi logging
# bridge used by WSO2 Carbon) parses this line as an un-typed component and
# throws a ConfigurationException, which prevents the pax-logging bundle from
# starting and cascades into publisher / portal failures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

CHART_CACHE_DIR="${ROOT_DIR}/generated/charts"

for chart in wso2am-acp wso2am-tm wso2am-universal-gw; do
  log4j2="${CHART_CACHE_DIR}/${chart}/confs/log4j2.properties"
  if [[ ! -f "${log4j2}" ]]; then
    echo "log4j2.properties not found for ${chart} (expected at ${log4j2}); skipping." >&2
    continue
  fi
  if grep -q '^category\.SERVICE_APPENDER\._OpenService_' "${log4j2}"; then
    sed -i '/^category\.SERVICE_APPENDER\._OpenService_/d' "${log4j2}"
    echo "Removed log4j1 category. line from ${log4j2}"
  else
    echo "No log4j1 category. line found in ${log4j2} (already clean)."
  fi

  # Remove unrendered Helm template placeholders from the loggers list.
  # The chart's loggers line may end with ", {{ .Values.wso2.apim.log4j2.loggers }}"
  # which pax-logging tries to parse as a logger with no properties → ConfigurationException.
  if grep -q '{{' "${log4j2}"; then
    sed -i 's/, *{{ *\.Values\.[^}]* *}}//g' "${log4j2}"
    echo "Removed unrendered Helm placeholder(s) from loggers list in ${log4j2}"
  else
    echo "No Helm placeholders found in ${log4j2} (already clean)."
  fi
done
