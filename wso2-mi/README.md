# WSO2 Integrator: MI on Kubernetes (Stateless Multi-Replica)

This folder contains an idempotent deployment bundle for **WSO2 Integrator: MI** using Helm, following the same operational structure and script flow used in `wso2-apim`.

Target runtime:
- **WSO2 Integrator: MI 4.6.0**

Chart source:
- `wso2/helm-mi` repository (`mi` chart)
- Default chart ref in this bundle: `4.5.x` (runtime image/build are overridden to 4.6.0 in values)

Reference documentation:
- https://mi.docs.wso2.com/en/4.6.0/install-and-setup/setup/deployment/kubernetes-deployment-patterns/#multiple-replicas
- https://mi.docs.wso2.com/en/4.6.0/install-and-setup/setup/deployment/configuring-helm-charts/
- https://mi.docs.wso2.com/en/4.6.0/install-and-setup/setup/deployment/sample-k8s-deployment/

## What is included

- `values/mi-values.yaml.tmpl`: template for Helm values.
- `scripts/`: automation scripts for render, secrets, deploy, lint, and cleanup.
- `docker/mi.Dockerfile`: optional base image extension for JDBC/shared libs.
- `.env.example`: single source of environment-specific settings.
- `Makefile`: operator entry points.

## Deployment model

This setup is configured for **stateless multiple replicas**:
- `MI_REPLICAS=2` by default.
- Coordination is intentionally not enabled (appropriate for stateless integrations).
- No chart-managed persistent CApp mount is enabled.

## Prerequisites

- `kubectl`, `helm`, `git`, `bash`, `envsubst`
- `keytool` (only if `AUTO_GENERATE_KEYSTORES=true`)
- NGINX ingress or Gateway API controller (depending on your routing mode)

## Configure

1. Copy `.env.example` to `.env`.
2. Update `MI_HOSTNAME` and routing flags (`ENABLE_INGRESS` / `ENABLE_GATEWAY_API`).
3. Set WSO2 subscription credentials (`IMAGE_PULL_SECRET_USERNAME`, `IMAGE_PULL_SECRET_PASSWORD`).
4. Set custom registry credentials (`CUSTOM_IMAGE_PULL_SECRET_USERNAME`, `CUSTOM_IMAGE_PULL_SECRET_PASSWORD`) and confirm `MI_CUSTOM_IMAGE_REPOSITORY`.
5. Keep or adjust replica/resource settings.

Important defaults:
- `MI_IMAGE_TAG=4.6.0`
- `MI_BUILD_VERSION=4.6.0`
- `MI_REPLICAS=2`

## Commands

Deploy:

```bash
make deploy
```

`make deploy` executes:
1. Cluster connectivity check.
2. Build and push custom MI image to `${CUSTOM_IMAGE_REGISTRY}/${MI_CUSTOM_IMAGE_REPOSITORY}:${MI_IMAGE_TAG}` (unless `SKIP_IMAGE_BUILD=true`).
3. Namespace and secret preparation.
4. Helm values render, chart pull, and chart deploy.

Undeploy:

```bash
make undeploy
```

Optional validation scripts:

```bash
./scripts/render-values.sh .env && ./scripts/pull-charts.sh .env
./scripts/lint.sh .env
```

## Notes

- The `helm-mi` chart currently advertises chart/app version 4.5.0; this bundle runs MI 4.6.0 by overriding deployment image tag/build version through values.
- Subscription images require credentials for `docker.wso2.com`.
- Runtime pods pull from `CUSTOM_IMAGE_REGISTRY/MI_CUSTOM_IMAGE_REPOSITORY`, not directly from the subscription registry.
- Keystores can be auto-generated for non-production using `AUTO_GENERATE_KEYSTORES=true`.
