"""
Patch libodoo.sh to auto-detect an already-bootstrapped external database.

When using an external DB (e.g. AWS RDS) that survives Helm chart reinstalls
but the PVC is recreated (losing Bitnami's init marker at /bitnami/odoo/),
the Bitnami bootstrap would re-run --init on an already-populated database,
causing module data conflicts (e.g. "Can't edit default kinds").

This patch injects a lightweight DB check right before the --init decision.
If the ir_module_module table already exists, ODOO_SKIP_BOOTSTRAP is set
automatically so the existing database is preserved.
"""

import sys

LIBODOO = "/opt/bitnami/scripts/libodoo.sh"

TARGET = '        if ! is_boolean_yes "$ODOO_SKIP_BOOTSTRAP"; then'

INJECT = """\
        # DAD: Auto-detect re-install (PVC wiped but external DB retains modules)
        local _tbl_check
        _tbl_check="$(postgresql_remote_execute_print_output "${db_execute_args[@]}" <<< "SELECT 1 FROM information_schema.tables WHERE table_name='ir_module_module' LIMIT 1;" 2>/dev/null || true)"
        if [[ "$_tbl_check" == *"1"* ]]; then
            info "Database already bootstrapped - switching to skip-bootstrap mode"
            ODOO_SKIP_BOOTSTRAP=true
            ODOO_SKIP_MODULES_UPDATE=true
        fi
"""

with open(LIBODOO) as f:
    content = f.read()

if TARGET not in content:
    print(f"ERROR: patch target not found in {LIBODOO}", file=sys.stderr)
    sys.exit(1)

content = content.replace(TARGET, INJECT + TARGET, 1)

with open(LIBODOO, "w") as f:
    f.write(content)

print("Patched libodoo.sh: added auto-detect for existing database")
