#!/bin/bash
# ---------------------------------------------------------------------------
# apply-patches.sh — Apply build-time patches to the OpenG2P Social Registry.
#
# Patches are divided into two groups:
#   1. Core patches: Always applied. Fix upstream bugs or add required
#      configuration that the base image does not provide.
#   2. Dev patches:  Only applied when DEV_PATCHES=true. These relax
#      security constraints for local/dev environments (e.g. disable
#      SSL verification for self-signed certificates).
#
# Usage (in Dockerfile):
#   COPY patches/apply-patches.sh /tmp/apply-patches.sh
#   RUN bash /tmp/apply-patches.sh && rm /tmp/apply-patches.sh
#
# Env vars:
#   DEV_PATCHES  — set to "true" to enable dev-only patches (default: false)
# ---------------------------------------------------------------------------
set -euo pipefail

EXTRAADDONS="/opt/bitnami/odoo/extraaddons"
SCRIPTS="/opt/bitnami/scripts"

echo "=== Applying core patches ==="

# ---------------------------------------------------------------------------
# 1. Patch odoo.conf template: include extra-addon directories in addons_path
#    from first boot. The base image delays this to post-init-openg2p.sh which
#    runs AFTER bootstrap, causing --init to miss OpenG2P modules.
# ---------------------------------------------------------------------------
echo "[patch] odoo.conf.tpl: add extra-addon dirs to addons_path"
sed -i \
    's|^addons_path = {{ODOO_ADDONS_DIR}}$|addons_path = {{ODOO_ADDONS_DIR}},'"${EXTRAADDONS}"'/oca,'"${EXTRAADDONS}"'/openg2p-registry,'"${EXTRAADDONS}"'/openg2p-social-registry,'"${EXTRAADDONS}"'/dad|' \
    "${SCRIPTS}/odoo/bitnami-templates/odoo.conf.tpl"

# ---------------------------------------------------------------------------
# 2. Patch libodoo.sh: configurable --init module list via ODOO_INIT_MODULES.
# ---------------------------------------------------------------------------
echo "[patch] libodoo.sh: configurable ODOO_INIT_MODULES"
sed -i \
    's|local -a init_args=("--init=all")|local -a init_args=("--init=${ODOO_INIT_MODULES:-all}")|' \
    "${SCRIPTS}/libodoo.sh"

# ---------------------------------------------------------------------------
# 2b. Patch odoo_conf_get: return only last match for duplicate INI keys.
#     Odoo's save() appends db_password a second time at end-of-file.
#     Without this, odoo_conf_get returns a multi-line value which breaks
#     the Bitnami postgresql_execute_print_output() password check.
# ---------------------------------------------------------------------------
echo "[patch] libodoo.sh: odoo_conf_get tail -1 for duplicate keys"
sed -i \
    's#grep -E "$sanitized_pattern" "$ODOO_CONF_FILE" | sed#grep -E "$sanitized_pattern" "$ODOO_CONF_FILE" | tail -1 | sed#' \
    "${SCRIPTS}/libodoo.sh"

# ---------------------------------------------------------------------------
# 2c. Patch run.sh: deduplicate odoo.conf keys before starting Odoo.
#     Odoo's configmanager.save() appends db_password and server_wide_modules
#     to the end of odoo.conf, creating duplicates. Python's configparser
#     (strict=True) raises DuplicateOptionError on these duplicates.
#     This patch removes earlier occurrences, keeping the last value per key.
# ---------------------------------------------------------------------------
echo "[patch] run.sh: deduplicate odoo.conf before Odoo start"
sed -i '/^info "\*\* Starting Odoo \*\*"/i \
# Deduplicate INI keys in odoo.conf (keep first occurrence, remove later duplicates)\
if [[ -f "$ODOO_CONF_FILE" ]]; then\
    awk '"'"'/^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=/ {\
        key = $0; sub(/[[:space:]]*=.*/, "", key); sub(/^[[:space:]]*/, "", key);\
        if (seen[key]++) next\
    } { print }'"'"' "$ODOO_CONF_FILE" > "${ODOO_CONF_FILE}.tmp" && mv "${ODOO_CONF_FILE}.tmp" "$ODOO_CONF_FILE"\
fi' "${SCRIPTS}/odoo/run.sh"

# ---------------------------------------------------------------------------
# 3. Patch libodoo.sh: auto-detect already-bootstrapped external database.
# ---------------------------------------------------------------------------
echo "[patch] libodoo.sh: auto-detect existing database"
python3 /tmp/detect-existing-db.py

# ---------------------------------------------------------------------------
# 4. Patch _auth_oauth_signin: email-based fallback for first OIDC login.
#    When oauth_uid is not yet set (first login), Odoo cannot match the
#    Keycloak sub claim to an existing user and tries to create a duplicate,
#    which crashes with UniqueViolation on res_users_login_key.
#    This patch adds a fallback: if no user matches (provider, oauth_uid),
#    try (provider, login=email) and auto-link the oauth_uid.
# ---------------------------------------------------------------------------
echo "[patch] res_users.py: email-based fallback in _auth_oauth_signin"
OIDC_RES_USERS="${EXTRAADDONS}/openg2p-registry/g2p_auth_oidc/models/res_users.py"
python3 - "$OIDC_RES_USERS" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r") as f:
    src = f.read()

old = '''\
            oauth_user = self.search([("oauth_uid", "=", oauth_uid), ("oauth_provider_id", "=", provider)])
            if not oauth_user:
                raise AccessDenied()'''

new = '''\
            oauth_user = self.search([("oauth_uid", "=", oauth_uid), ("oauth_provider_id", "=", provider)])
            if not oauth_user:
                # Fallback: match by email + provider and auto-link oauth_uid (first login)
                email = validation.get("email")
                if email:
                    oauth_user = self.search([("login", "=", email), ("oauth_provider_id", "=", provider)], limit=1)
                    if oauth_user:
                        oauth_user.write({"oauth_uid": oauth_uid})
                        _logger.info("OIDC: linked existing user %s to oauth_uid %s", email, oauth_uid)
                if not oauth_user:
                    raise AccessDenied()'''

if old not in src:
    print("WARNING: target code block not found in " + path, file=sys.stderr)
    sys.exit(1)

src = src.replace(old, new, 1)
with open(path, "w") as f:
    f.write(src)
print("  -> Patched _auth_oauth_signin email fallback")
PYEOF

# ---------------------------------------------------------------------------
# 5. Fix upstream bug: g2p_documents/preview_document.js missing export.
#    Fixed in https://github.com/OpenG2P/openg2p-registry/pull/288
#    but not included in base image 1.5.7.
# ---------------------------------------------------------------------------
echo "[patch] preview_document.js: export Widgetpreview class"
sed -i \
    's|^class G2PDocumentPreview|export class Widgetpreview|' \
    "${EXTRAADDONS}/openg2p-registry/g2p_documents/static/src/js/preview_document.js"
sed -i \
    's|G2PDocumentPreview\.template|Widgetpreview.template|; s|component: G2PDocumentPreview|component: Widgetpreview|' \
    "${EXTRAADDONS}/openg2p-registry/g2p_documents/static/src/js/preview_document.js"

# ---------------------------------------------------------------------------
# Dev-only patches (behind DEV_PATCHES flag)
# ---------------------------------------------------------------------------
if [[ "${DEV_PATCHES:-false}" == "true" ]]; then
    echo ""
    echo "=== Applying dev-only patches (DEV_PATCHES=true) ==="

    # -----------------------------------------------------------------------
    # 6. Disable SSL verification and add retry on OIDC requests.
    #    Required when Keycloak sits behind a reverse proxy with a
    #    self-signed certificate that resets rapid successive TLS
    #    handshakes (e.g. OpenShift edge routes).
    # -----------------------------------------------------------------------
    echo "[dev-patch] auth_oauth_provider.py: verify=False + retry session"
    OIDC_PROVIDER="${EXTRAADDONS}/openg2p-registry/g2p_auth_oidc/models/auth_oauth_provider.py"
    python3 - "$OIDC_PROVIDER" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r") as f:
    src = f.read()

import_block = "import requests"
retry_helper = """import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry as _Retry

def _retry_session():
    s = requests.Session()
    s.verify = False
    retries = _Retry(total=3, backoff_factor=1,
                     status_forcelist=[502, 503, 504],
                     method_whitelist=["GET", "POST"])
    adapter = HTTPAdapter(max_retries=retries)
    s.mount("https://", adapter)
    s.mount("http://", adapter)
    return s"""

if import_block not in src:
    print("WARNING: 'import requests' not found in " + path, file=sys.stderr)
    sys.exit(1)

src = src.replace(import_block, retry_helper, 1)
src = src.replace("requests.post(", "_retry_session().post(")
src = src.replace("requests.get(", "_retry_session().get(")

with open(path, "w") as f:
    f.write(src)
print("  -> Patched auth_oauth_provider.py with retry session + verify=False")
PYEOF

    echo "[dev-patch] res_users.py: verify=False + retry session"
    OIDC_RES_USERS_RETRY="${EXTRAADDONS}/openg2p-registry/g2p_auth_oidc/models/res_users.py"
    python3 - "$OIDC_RES_USERS_RETRY" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r") as f:
    src = f.read()

import_block = "import requests"
retry_helper = """import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry as _Retry

def _retry_session():
    s = requests.Session()
    s.verify = False
    retries = _Retry(total=3, backoff_factor=1,
                     status_forcelist=[502, 503, 504],
                     method_whitelist=["GET", "POST"])
    adapter = HTTPAdapter(max_retries=retries)
    s.mount("https://", adapter)
    s.mount("http://", adapter)
    return s"""

if import_block not in src:
    print("WARNING: 'import requests' not found in " + path, file=sys.stderr)
    sys.exit(1)

src = src.replace(import_block, retry_helper, 1)
src = src.replace("requests.get(", "_retry_session().get(")
src = src.replace("requests.post(", "_retry_session().post(")

with open(path, "w") as f:
    f.write(src)
print("  -> Patched res_users.py with retry session + verify=False")
PYEOF

else
    echo ""
    echo "=== Dev patches skipped (DEV_PATCHES != true) ==="
fi

echo ""
echo "=== All patches applied ==="
