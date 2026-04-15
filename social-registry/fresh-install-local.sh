#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# fresh-install.sh — Tear down, wipe DB, and reinstall the farmer-registry
#                     Helm chart from scratch.
#
# Usage:
#   ./fresh-install-local.sh                      # defaults
#   RELEASE=my-release NS=my-ns ./fresh-install-local.sh
# ---------------------------------------------------------------------------
set -euo pipefail

RELEASE="${RELEASE:-dad-farmer-registry}"
NS="${NS:-farmer-registry}"
CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PG_POD="${PG_POD:-pg-postgresql-0}"
DB_USER="${DB_USER:-social_registry_local}"
DB_NAME="${DB_NAME:-social_registry_local}"
DB_PASS="${DB_PASS:-localpass123}"

echo "=== Uninstalling Helm release '${RELEASE}' ==="
helm uninstall "${RELEASE}" -n "${NS}" 2>/dev/null || echo "(already uninstalled)"

echo "=== Deleting PVCs ==="
kubectl delete pvc -n "${NS}" -l "app.kubernetes.io/instance=${RELEASE}" --ignore-not-found

echo "=== Dropping and recreating database '${DB_NAME}' ==="
kubectl exec -n "${NS}" "${PG_POD}" -- bash -c \
  "PGPASSWORD='${DB_PASS}' psql -U '${DB_USER}' -d postgres \
     -c 'DROP DATABASE IF EXISTS ${DB_NAME};' \
     -c 'CREATE DATABASE ${DB_NAME};'"

echo "=== Installing Helm chart ==="
cd "${CHART_DIR}"
helm install "${RELEASE}" . \
  -f values.yaml \
  -f values-local.yaml \
  -n "${NS}"

echo ""
echo "=== Done. Watch bootstrap progress with: ==="
echo "  kubectl logs -n ${NS} deploy/${RELEASE}-social-registry -c odoo -f"
