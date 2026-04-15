"""
Auto-configure Keycloak OIDC provider in Odoo on first boot.

Reads OIDC_ISSUER_URL, OIDC_CLIENT_ID, and OIDC_CLIENT_SECRET from
environment variables (injected by the Helm chart) and upserts an
auth_oauth_provider record in the database.  Also sets the system
parameters needed for OIDC user auto-creation (auth_signup.*, etc.).

Designed to run as a startup init script via
/docker-entrypoint-init.d/20-keycloak-oidc.sh (after DB bootstrap).
"""

import base64
import json
import os
import secrets
import subprocess
import sys


def _psql(sql, *, fetch=False):
    """Execute SQL against the Odoo database using psql."""
    cmd = [
        "psql",
        "-h", os.environ["ODOO_DATABASE_HOST"],
        "-p", os.environ.get("ODOO_DATABASE_PORT_NUMBER", "5432"),
        "-U", os.environ["ODOO_DATABASE_USER"],
        "-d", os.environ["ODOO_DATABASE_NAME"],
        "-t", "-A",
        "-c", sql,
    ]
    env = {
        **os.environ,
        "PGPASSWORD": os.environ["ODOO_DATABASE_PASSWORD"],
        "PGSSLMODE": os.environ.get("DB_SSLMODE", "require"),
    }
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        print(f"psql error: {result.stderr.strip()}", file=sys.stderr)
        return None
    return result.stdout.strip() if fetch else True


def main():
    issuer_url = os.environ.get("OIDC_ISSUER_URL", "").strip()
    client_id = os.environ.get("OIDC_CLIENT_ID", "").strip()
    client_secret = os.environ.get("OIDC_CLIENT_SECRET", "").strip()

    if not issuer_url or not client_id:
        print("Keycloak OIDC: OIDC_ISSUER_URL or OIDC_CLIENT_ID not set — skipping auto-config.")
        return

    # Derive OIDC endpoints from the issuer URL
    base = issuer_url.rstrip("/")
    oidc = f"{base}/protocol/openid-connect"
    auth_endpoint = f"{oidc}/auth"
    token_endpoint = f"{oidc}/token"
    validation_endpoint = f"{oidc}/userinfo"
    data_endpoint = validation_endpoint
    jwks_uri = f"{oidc}/certs"
    logout_uri = f"{oidc}/logout"

    token_map = "sub:user_id name:name email:email phone_number:phone birthdate:birthdate picture:picture groups:groups"

    # Generate PKCE code_verifier (URL-safe base64, 43 chars)
    code_verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode("ascii")

    # Escape single quotes for SQL
    def q(s):
        return s.replace("'", "''")

    # Check if a provider with this client_id already exists
    existing = _psql(
        f"SELECT id FROM auth_oauth_provider WHERE client_id = '{q(client_id)}' LIMIT 1;",
        fetch=True,
    )

    if existing:
        provider_id = existing.strip()
        print(f"Keycloak OIDC: updating existing provider id={provider_id}")
        _psql(f"""
            UPDATE auth_oauth_provider SET
                name = 'Keycloak',
                auth_endpoint = '{q(auth_endpoint)}',
                token_endpoint = '{q(token_endpoint)}',
                validation_endpoint = '{q(validation_endpoint)}',
                data_endpoint = '{q(data_endpoint)}',
                jwks_uri = '{q(jwks_uri)}',
                logout_uri = '{q(logout_uri)}',
                client_secret = '{q(client_secret)}',
                scope = 'openid profile email',
                flow = 'oidc_auth_code',
                client_authentication_method = 'client_secret_post',
                token_map = '{q(token_map)}',
                allow_signup = 'yes',
                enabled = true,
                body = '{q(json.dumps({"en_US": "Login with Keycloak"}))}',
                css_class = 'fa fa-fw fa-sign-in text-primary',
                enable_pkce = true,
                verify_at_hash = true,
                code_verifier = '{q(code_verifier)}',
                write_date = NOW()
            WHERE id = {provider_id};
        """)
    else:
        print("Keycloak OIDC: creating new provider")
        _psql(f"""
            INSERT INTO auth_oauth_provider (
                name, client_id, auth_endpoint, token_endpoint,
                validation_endpoint, data_endpoint, jwks_uri, logout_uri,
                client_secret, scope, flow, client_authentication_method,
                token_map, allow_signup, enabled, body, css_class,
                enable_pkce, verify_at_hash, code_verifier, sequence,
                create_uid, write_uid, create_date, write_date
            ) VALUES (
                'Keycloak',
                '{q(client_id)}',
                '{q(auth_endpoint)}',
                '{q(token_endpoint)}',
                '{q(validation_endpoint)}',
                '{q(data_endpoint)}',
                '{q(jwks_uri)}',
                '{q(logout_uri)}',
                '{q(client_secret)}',
                'openid profile email',
                'oidc_auth_code',
                'client_secret_post',
                '{q(token_map)}',
                'yes',
                true,
                '{q(json.dumps({"en_US": "Login with Keycloak"}))}',
                'fa fa-fw fa-sign-in text-primary',
                true,
                true,
                '{q(code_verifier)}',
                10,
                1, 1, NOW(), NOW()
            );
        """)

    # Set system parameters for OIDC user auto-creation
    params = {
        "auth_oauth.authorization_header": "True",
        "auth_signup.invitation_scope": "b2c",
        "auth_signup.reset_password": "True",
    }
    for key, value in params.items():
        _psql(f"""
            INSERT INTO ir_config_parameter (key, value, create_uid, write_uid, create_date, write_date)
            VALUES ('{q(key)}', '{q(value)}', 1, 1, NOW(), NOW())
            ON CONFLICT (key) DO UPDATE SET value = '{q(value)}', write_date = NOW();
        """)

    # Disable all non-Keycloak OAuth providers (Facebook, Google, Odoo.com, etc.)
    _psql(f"""
        UPDATE auth_oauth_provider
        SET enabled = false, write_date = NOW()
        WHERE client_id != '{q(client_id)}' AND enabled = true;
    """)
    print("Keycloak OIDC: disabled all non-Keycloak OAuth providers.")

    # Link the Odoo admin user to Keycloak if their email matches
    # the ODOO_EMAIL env var. This prevents duplicate key violations when
    # the admin tries to log in via Keycloak for the first time.
    admin_email = os.environ.get("ODOO_EMAIL", "").strip()
    if admin_email:
        # Find the Keycloak provider id we just upserted
        pid = _psql(
            f"SELECT id FROM auth_oauth_provider WHERE client_id = '{q(client_id)}' LIMIT 1;",
            fetch=True,
        )
        if pid:
            pid = pid.strip()
            already = _psql(
                f"SELECT oauth_uid FROM res_users WHERE login = '{q(admin_email)}' AND oauth_provider_id = {pid};",
                fetch=True,
            )
            if not already or not already.strip():
                _psql(f"""
                    UPDATE res_users
                    SET oauth_provider_id = {pid}
                    WHERE login = '{q(admin_email)}' AND oauth_provider_id IS NULL;
                """)
                print(f"Keycloak OIDC: linked admin user '{admin_email}' to provider {pid} (oauth_uid will be set on first login).")
            else:
                print(f"Keycloak OIDC: admin user '{admin_email}' already linked to provider {pid}.")

    print("Keycloak OIDC: auto-configuration complete.")


if __name__ == "__main__":
    main()
