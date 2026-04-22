#!/usr/bin/env bash
set -euo pipefail

# Upstream WSO2 Helm charts are consumed directly; local files are templates and scripts.
# There is no safe auto-fix step for chart-level lint warnings in this bundle.
echo "No automatic lint-fix actions are defined. Skipping."
