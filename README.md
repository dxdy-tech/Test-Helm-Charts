# DAD Farmer Registry — Helm Chart

Umbrella Helm chart for deploying the **DAD Farmer Registry** on a Rancher-managed Kubernetes cluster.  Built on [OpenG2P Social Registry](https://github.com/OpenG2P/openg2p-social-registry) (Odoo 17) with an in-cluster **ODK Central** deployment for field data collection.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Components](#components)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Install / Upgrade](#install--upgrade)
6. [Dependency Model](#dependency-model)
7. [Configuration Reference](#configuration-reference)
8. [External Services Wiring](#external-services-wiring)
9. [ODK Central Deployment](#odk-central-deployment)
10. [Custom Social Registry Image](#custom-social-registry-image)
11. [Odoo Module Configuration](#odoo-module-configuration)
12. [Adding Future DAD Modules](#adding-future-dad-modules)
13. [Environment-Specific Values](#environment-specific-values)
14. [Design Decisions](#design-decisions)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│               Kubernetes Cluster (Rancher)              │
│                                                         │
│  ┌──────────────────────┐  ┌──────────────────────────┐ │
│  │   Social Registry    │  │      ODK Central         │ │
│  │   (Odoo 17 +         │  │  ┌─────────┐             │ │
│  │    OpenG2P addons)   │  │  │ Backend │             │ │
│  │                      │  │  └────┬────┘             │ │
│  │  ┌────────────────┐  │  │  ┌────┴────┐             │ │
│  │  │  Custom Image  │  │  │  │Frontend │             │ │
│  │  │  (Odoo + mods) │  │  │  │ (nginx) │             │ │
│  │  └────────────────┘  │  │  └─────────┘             │ │
│  │         │            │  │  ┌────────┐ ┌────────┐   │ │
│  │         │            │  │  │Enketo  │ │Pyxform │   │ │
│  │         │            │  │  └────────┘ └────────┘   │ │
│  └────┬────┴────────────┘  └─────────┬────────────────┘ │
│       │                              │                  │
│  ┌────┴───────────────────────────────┴──────────────┐  │
│  │                  Kubernetes Ingress               │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
└──────────┬──────────┬──────────┬────────────────────────┘
           │          │          │
    ┌──────┴───┐ ┌────┴─────┐ ┌──┴───────┐
    │PostgreSQL│ │Keycloak  │ │ MinIO    │
    │(external)│ │(external)│ │(external)│
    └──────────┘ └──────────┘ └──────────┘
```

---

## Components

| Component | Controlled By | Default |
|-----------|--------------|---------|
| Social Registry (Odoo 17 / OpenG2P) | `socialRegistry.enabled` | `true` |
| ODK Central (Backend + Frontend + Enketo + Pyxform) | `odkCentral.enabled` | `true` |
| ODK Central internal PostgreSQL | `odkCentral.database.internal.enabled` | `false` |

Each component can be independently enabled or disabled.

---

## Prerequisites

- Kubernetes 1.25+
- Helm 3.10+
- Rancher-managed cluster (any Kubernetes distribution)
- NGINX Ingress Controller (or compatible)
- **External** PostgreSQL instance (for Social Registry)
- **External** Keycloak instance
- **External** MinIO / S3-compatible storage
- (Optional) External NFS for shared persistence
- Pre-built custom Social Registry Docker image (see [Custom Image](#custom-social-registry-image))

---

## Quick Start

```bash
# Add any private Helm registry if needed
# helm registry login registry.example.com

# Install with dev overrides
helm install dad-farmer-registry ./farmer-registry \
  -n farmer-registry --create-namespace \
  -f farmer-registry/values.yaml \
  -f farmer-registry/values-dev.yaml
```

---

## Install / Upgrade

### Fresh install

```bash
helm install dad-farmer-registry ./farmer-registry \
  -n farmer-registry --create-namespace \
  -f values.yaml \
  -f values-<env>.yaml
```

### Upgrade

```bash
helm upgrade dad-farmer-registry ./farmer-registry \
  -n farmer-registry \
  -f values.yaml \
  -f values-<env>.yaml
```

### Uninstall

```bash
helm uninstall dad-farmer-registry -n farmer-registry
```

> **Note**: PVCs with `helm.sh/resource-policy: keep` will survive uninstall.

---

## Dependency Model

This chart has **no subchart dependencies**. All components are rendered from first-party templates within the umbrella chart directory:

```
farmer-registry/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── NOTES.txt
│   ├── social-registry/
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   ├── hpa.yaml
│   │   ├── ingress.yaml
│   │   ├── networkpolicy.yaml
│   │   ├── pdb.yaml
│   │   ├── pvc.yaml
│   │   ├── service.yaml
│   │   └── serviceaccount.yaml
│   └── odk-central/
│       ├── configmap.yaml
│       ├── deployment.yaml
│       ├── enketo.yaml
│       ├── hpa.yaml
│       ├── ingress.yaml
│       ├── networkpolicy.yaml
│       ├── pdb.yaml
│       ├── postgresql.yaml
│       ├── pvc.yaml
│       ├── pyxform.yaml
│       ├── service.yaml
│       └── serviceaccount.yaml
```

External services (PostgreSQL, Keycloak, MinIO) are consumed via configuration values — no in-cluster subcharts are deployed for them.

---

## Configuration Reference

See `values.yaml` for the full schema. Key sections:

### Social Registry

| Parameter | Description | Default |
|-----------|-------------|---------|
| `socialRegistry.enabled` | Deploy Social Registry | `true` |
| `socialRegistry.image.repository` | Custom Odoo image | `""` |
| `socialRegistry.image.tag` | Image tag | `""` |
| `socialRegistry.ingress.hostname` | Ingress hostname | `""` |
| `socialRegistry.externalPostgresql.*` | External PG connection | — |
| `socialRegistry.externalKeycloak.*` | External Keycloak OIDC | — |
| `socialRegistry.externalMinio.*` | External S3 storage | — |
| `socialRegistry.odkIntegration.*` | ODK Central URL/token | — |
| `socialRegistry.odoo.modules` | Module list (see below) | `[...]` |
| `socialRegistry.odoo.autoInstallModules` | Auto-install on startup | `false` |
| `socialRegistry.resources` | CPU/memory requests/limits | 500m/1Gi — 2/4Gi |
| `socialRegistry.autoscaling.*` | HPA configuration | disabled |
| `socialRegistry.persistence.*` | PVC for Odoo filestore | 10Gi RWX |

### ODK Central

| Parameter | Description | Default |
|-----------|-------------|---------|
| `odkCentral.enabled` | Deploy ODK Central | `true` |
| `odkCentral.ingress.hostname` | Ingress hostname | `""` |
| `odkCentral.admin.email` | System admin email | `""` |
| `odkCentral.database.internal.enabled` | Deploy in-cluster PG | `false` |
| `odkCentral.database.external.*` | External PG connection | — |
| `odkCentral.enketo.enabled` | Deploy Enketo service | `true` |
| `odkCentral.pyxform.enabled` | Deploy Pyxform service | `true` |
| `odkCentral.resources` | CPU/memory requests/limits | 250m/512Mi — 1/2Gi |

---

## External Services Wiring

### PostgreSQL (Social Registry)

Social Registry does **not** deploy its own PostgreSQL. Provide connection details:

```yaml
socialRegistry:
  externalPostgresql:
    host: postgres.example.com
    port: 5432
    database: socialregistrydb
    username: sruser
    existingSecret: sr-pg-secret      # must contain key "password"
    sslmode: require
```

Create the secret before installing the chart:

```bash
kubectl create secret generic sr-pg-secret \
  --from-literal=password='<your-password>' \
  -n farmer-registry
```

### Keycloak

```yaml
socialRegistry:
  externalKeycloak:
    issuerUrl: https://keycloak.example.com/realms/master
    baseUrl: https://keycloak.example.com
    realm: master
    clientId: openg2p-sr
    existingSecret: sr-kc-secret      # must contain key "client-secret"
```

### MinIO / S3

```yaml
socialRegistry:
  externalMinio:
    endpoint: minio.example.com:9000
    bucket: social-registry
    secure: true
    existingSecret: sr-minio-secret   # must contain "access-key" and "secret-key"
```

---

## ODK Central Deployment

ODK Central is deployed as its own set of workloads within this umbrella chart — it is **not** embedded into the Odoo container. Components:

- **Backend**: Node.js application (`ghcr.io/getodk/central-backend`)
- **Frontend**: NGINX reverse proxy (`ghcr.io/getodk/central-nginx`)
- **Enketo**: Form rendering engine
- **Pyxform**: XLSForm converter

### Database options

- **External** (default): Set `odkCentral.database.external.*`
- **Internal**: Set `odkCentral.database.internal.enabled: true` to deploy a single-replica PostgreSQL StatefulSet (suitable for dev/test only)

### Integration with Social Registry

Social Registry connects to ODK Central through:
- `socialRegistry.odkIntegration.centralUrl` — the ODK Central URL
- `socialRegistry.odkIntegration.existingSecret` — API token for programmatic access

These values are consumed by the `g2p_odk_importer` and `g2p_odk_user_mapping` Odoo modules.

---

## Custom Social Registry Image

The Social Registry deployment expects a **prebuilt custom Docker image** that extends Odoo 17 with OpenG2P addons.

### Sample Dockerfile

```dockerfile
FROM odoo:17

# Install system dependencies
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy OpenG2P addons
COPY ./addons/openg2p /mnt/extra-addons/openg2p

# Copy DAD custom addons (when ready)
# COPY ./addons/dad /mnt/extra-addons/dad

# Set addons path
ENV ODOO_EXTRA_ADDONS=/mnt/extra-addons/openg2p,/mnt/extra-addons/dad

USER odoo
```

### How to point to your image

```yaml
socialRegistry:
  image:
    repository: registry.example.com/dad-farmer-registry
    tag: "1.0.0"
    pullPolicy: IfNotPresent
  imagePullSecrets:
    - name: registry-credentials
```

---

## Odoo Module Configuration

### How it works

The module list is defined in `socialRegistry.odoo.modules` as a simple YAML array. At template time, Helm joins the list into a comma-separated string and passes it to the Odoo container as the `ODOO_MODULES` environment variable. The `ODOO_AUTO_INSTALL_MODULES` env var controls whether Odoo should attempt to auto-install them on startup.

**Helm does NOT validate whether the listed modules exist in the image.** This is intentional. The chart's job is to pass configuration; the custom image is solely responsible for containing the addons.

### Default modules

```yaml
socialRegistry:
  odoo:
    modules:
      - g2p_agent_portal_base
      - g2p_registry_individual
      - g2p_registry_group
      - g2p_registry_membership
      - g2p_registry_dashboard
      - g2p_registry_theme
      - g2p_odk_importer
      - g2p_registry_rest_api
      - g2p_registry_deduplication_deduplicator
      - g2p_registration_portal_base
      - g2p_odk_user_mapping
```

### Safe startup behavior

| `autoInstallModules` | Behavior |
|---------------------|----------|
| `false` (default) | Module names are available as env vars but Odoo does **not** force-install them. The operator must trigger installation via the Odoo UI or CLI. |
| `true` | Odoo will attempt to install/update the listed modules on startup. Only enable this after confirming the image contains all listed modules. |

---

## Adding Future DAD Modules

When DAD-specific modules (e.g., `dad_farmer_registry`, `dad_rest_api`) are ready:

1. **Build them into the custom image** — add the addon directories to the Dockerfile.
2. **Uncomment in values.yaml** (or add to your environment override):

   ```yaml
   socialRegistry:
     odoo:
       modules:
         # ... existing modules ...
         - dad_farmer_registry
         - dad_rest_api
   ```

3. **Upgrade the release**:

   ```bash
   helm upgrade dad-farmer-registry ./farmer-registry \
     -f values.yaml -f values-prod.yaml
   ```

4. If `autoInstallModules` is `false`, install the modules manually through the Odoo Apps UI or via CLI:

   ```bash
   kubectl exec -it deploy/<release>-social-registry -n farmer-registry -- \
     odoo -d socialregistrydb -i dad_farmer_registry,dad_rest_api --stop-after-init
   ```

No Helm template changes are required — just add module names to the list and ensure they exist in the image.

---

## Environment-Specific Values

| File | Purpose |
|------|---------|
| `values.yaml` | Base defaults (required) |
| `values-dev.yaml` | Development — relaxed security, auto-install on |
| `values-qe.yaml` | QE / Testing |
| `values-uat.yaml` | UAT — TLS enabled, autoscaling |
| `values-prod.yaml` | Production — full HA, strict resources |

Usage:

```bash
helm install ... -f values.yaml -f values-prod.yaml
```

---

## Design Decisions

### Why external PostgreSQL / Keycloak / MinIO for Social Registry?

Production deployments typically require dedicated, managed instances of these stateful services with their own backup/HA strategies. Bundling them as subcharts creates operational coupling, complicates upgrades, and limits the ability to share instances across multiple applications. The chart consumes externally provisioned services via connection parameters and existing Kubernetes Secrets.

### Why ODK Central is deployed separately within the umbrella chart?

ODK Central is a distinct application (Node.js backend + NGINX frontend) that should not be embedded into the Odoo container. It has its own lifecycle, scaling characteristics, and failure domain. Deploying it as a separate set of workloads within the umbrella chart allows:
- Independent scaling of ODK and Odoo
- Separate health monitoring and restart policies
- Clean network boundaries via NetworkPolicy
- The ability to disable it entirely (`odkCentral.enabled: false`) without affecting Social Registry

### Why a custom image for addons?

OpenG2P addons are Python packages that must be present in the Odoo filesystem at startup. Baking them into a custom image (rather than fetching at runtime) ensures:
- Deterministic deployments — the image tag pins the exact addon versions
- Faster startup — no git clone or pip install at boot time
- Immutable containers — critical for security scanning and compliance
- Works cleanly in air-gapped or restricted environments

### Why module names are configurable but not validated by Helm?

Helm operates at templating time, before any container runs. It has no way to inspect the filesystem of a Docker image. Attempting to validate module names during `helm template` would require either:
- Hardcoding a list (defeats the purpose of configurability)
- Reaching out to a registry API (fragile, slow, auth-complex)

Instead, the chart trusts the operator to keep the module list and the image contents in sync. Module names are passed into environment variables as simple strings. The Odoo runtime handles discovery and installation.

### How future DAD custom modules plug in

The `socialRegistry.odoo.modules` list is a plain YAML array. To add `dad_farmer_registry` or `dad_rest_api`:
1. Include the addons in the custom Docker image
2. Append the module names to the array
3. Redeploy

No template changes, no chart version bump, no subchart additions. The existing commented placeholders in `values.yaml` serve as documentation.
