# WSO2 API Manager Pattern 3 on RKE2 (PostgreSQL)

This folder contains a repeatable and idempotent deployment bundle for **WSO2 API Manager Pattern 3** (ACP + TM + Universal GW) using Helm on your RKE2 cluster.

Reference documentation:
- https://apim.docs.wso2.com/en/latest/install-and-setup/setup/kubernetes-deployment/kubernetes/am-pattern-3-acp-tm-gw/

## What is included

- `values/*.yaml.tmpl`: component value templates for ACP, TM, and GW.
- `scripts/`: automation scripts for render, secrets, deploy, validate, and cleanup.
- `docker/*.Dockerfile`: optional component Dockerfiles that add the PostgreSQL JDBC driver.
- `.env.example`: single source of environment-specific settings.
- `Makefile`: operator entry points (`deploy`, `undeploy`).

## Idempotency guarantees

- Namespace and secrets are applied with `kubectl apply` or `create --dry-run=client -o yaml | apply`.
- Helm releases are applied with `helm upgrade --install`.
- Value rendering always overwrites generated outputs deterministically.
- DB/user preparation script creates principals and databases only when missing.
- First deploy auto-runs DB prep and PostgreSQL schema bootstrap when both Helm releases and schema sentinels are absent.

## Prerequisites

- `kubectl`, `helm`, `bash`
- `envsubst` (for values rendering)
- `curl` or `wget` in container images (used by startup script JDBC auto-download)
- `keytool` (if auto-generating keystores)
- `psql` (only if you explicitly use local DB prep/schema mode)

Your kubeconfig is expected at:
- `/home/chamath/Downloads/openg2p-dad.yaml`

## Configure

1. Copy `.env.example` to `.env`.
2. Update hostnames in `.env`:
   - `CONTROL_PLANE_HOSTNAME`
   - `GW_HOSTNAME`
   - `WS_HOSTNAME`
   - `WEBSUB_HOSTNAME`
3. Update APIM admin credentials and DB password before production.
4. Set image tags in `.env`; deployment uses tag-based image references for compatibility with the WSO2 private registry.
5. `POSTGRES_JDBC_VERSION` controls the PostgreSQL JDBC jar version downloaded at startup.
6. `POSTGRES_JDBC_URL` can optionally override the download location (for internal mirrors).
7. Subscription images are mandatory and controlled by:
   - `IMAGE_REGISTRY=docker.wso2.com`
   - `IMAGE_PULL_SECRET_USERNAME` / `IMAGE_PULL_SECRET_PASSWORD` (same credentials used for `docker login docker.wso2.com`)
   - `IMAGE_PULL_SECRET_NAME` (shared pull secret name for app and helper pods)
8. Resource names are fixed to the following:
   - Deployments: `apim-control-plane-1`, `apim-control-plane-2`, `apim-traffic-manager-1`, `apim-traffic-manager-2`, `apim-gateway`
   - Services: `apim-control-plane-service`, `apim-control-plane-1-service`, `apim-control-plane-2-service`, `apim-traffic-manager-service`, `apim-traffic-manager-1-service`, `apim-traffic-manager-2-service`, `apim-gateway-service`
9. If your cluster API watch streams are unstable, keep `HELM_WAIT=false`.
10. If gateway pods are pending due CPU pressure, reduce `GW_CPU_REQUEST` and `GW_MEMORY_REQUEST` in `.env`.

## Deploy Behavior

`make deploy` now performs these steps:

1. Checks if any APIM Helm release already exists.
2. Checks if schema sentinel tables exist in both DBs.
3. If both are absent, it treats this as first-time install and runs:
   - DB user/database preparation
   - automatic WSO2 PostgreSQL schema bootstrap (shared + apimgt)
4. Renders values, creates secrets, pulls/patches charts, and deploys ACP/TM/GW.

On update/redeploy, DB prep/schema bootstrap is skipped automatically.

`make undeploy` uninstalls ACP/TM/GW only and does not modify DB state.

Schema/bootstrap tuning variables:
- `DB_PREPARE_MODE` (`cluster` or `local`, default in `.env.example`: `cluster`)
- `DB_PREPARE_IMAGE` (default: `postgres:16-alpine`)
- `DB_PREPARE_TIMEOUT` (default: `300s`)
- `DB_PREPARE_CLEANUP_POD` (default: `true`)
- `SCHEMA_APPLY_MODE` (`cluster` or `local`, default in `.env.example`: `cluster`)
- `SCHEMA_SOURCE_IMAGE` (optional override image for sourcing dbscripts; default derives from ACP image repo/tag)
- `SCHEMA_CHECK_SHARED_TABLE` (default: `idn_base_table`)
- `SCHEMA_CHECK_APIM_TABLE` (default: `am_api`)

Cluster modes use polling instead of watch-based waits, making the flow resilient to unstable Kubernetes watch streams.

Rendered values disable chart-managed docker-registry secret creation and rely on a shared namespace pull secret.
Deploy creates/updates `IMAGE_PULL_SECRET_NAME` and patches the default ServiceAccount so both app and helper pods can pull private images.
`make deploy` validates subscription-only settings and fails early if registry/pull-secret settings are invalid or credentials are placeholders/missing.

## Build custom images (optional)

```bash
docker build -f docker/acp.Dockerfile -t <registry>/<acp-repo>:<tag> .
docker build -f docker/tm.Dockerfile -t <registry>/<tm-repo>:<tag> .
docker build -f docker/gw.Dockerfile -t <registry>/<gw-repo>:<tag> .
```

Then push and update `.env` image variables.

If you publish custom images, update the matching `*_IMAGE_TAG` values.

By default, the deploy workflow pulls charts locally and patches startup scripts to download the PostgreSQL JDBC jar from `POSTGRES_JDBC_URL` before APIM starts.

## Repeatable workflow

Deploy:

```bash
make deploy
```

Undeploy:

```bash
make undeploy
```

Internal helper scripts are still available under `scripts/` for diagnostics and validation (for example: `lint.sh`, `lint-fix.sh`, `test.sh`, `cluster-check.sh`).

## Notes

- Default release names are aligned with WSO2 Pattern 3 naming assumptions.
- ACP, TM, and GW are wired through fixed internal service names in the values templates.
- Keystore secret defaults to `apim-keystore-secret`; if files are not present, scripts can auto-generate JKS files for non-production use.
