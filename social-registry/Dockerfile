##
## Custom Social Registry image for DAD Farmer Registry.
##
## Build (from farmer-registry/social-registry/):
##   docker build --build-context farmer-addons=../../openg2p-farmer-registry \
##     -t vsoneworld/openg2pdad:0.0.8 \
##     -f Dockerfile.social-registry .
##
## Dev build (enables SSL-bypass patches for self-signed certs):
##   docker build --build-arg DEV_PATCHES=true \
##     --build-context farmer-addons=../openg2p-farmer-registry \
##     -t vsoneworld/openg2pdad:0.0.12-dev \
##     -f Dockerfile.social-registry .
##

ARG BASE_IMAGE=openg2p/openg2p-social-registry-core:1.5.7
FROM ${BASE_IMAGE}

USER root

# ---------------------------------------------------------------------------
# DEV_PATCHES: set to "true" to enable dev-only patches (e.g. verify=False
# for self-signed Keycloak certificates).  Default: false.
# ---------------------------------------------------------------------------
ARG DEV_PATCHES=false
ENV DEV_PATCHES=${DEV_PATCHES}

# ---------------------------------------------------------------------------
# Copy patch scripts and the Keycloak auto-config init script.
# ---------------------------------------------------------------------------
COPY patches/detect-existing-db.py /tmp/detect-existing-db.py
COPY patches/apply-patches.sh      /tmp/apply-patches.sh
COPY patches/configure-keycloak-oidc.py /opt/bitnami/odoo/patches/configure-keycloak-oidc.py

# ---------------------------------------------------------------------------
# Apply build-time patches (core + optionally dev).
# See patches/apply-patches.sh for details on each patch.
# ---------------------------------------------------------------------------
RUN bash /tmp/apply-patches.sh && rm /tmp/apply-patches.sh /tmp/detect-existing-db.py

# ---------------------------------------------------------------------------
# Layer DAD-specific addons from the openg2p-farmer-registry repo.
# Uses a named build context (--build-context farmer-addons=<path>).
# ---------------------------------------------------------------------------
COPY --from=farmer-addons g2p_farmer/  /opt/bitnami/odoo/extraaddons/dad/g2p_farmer/
COPY --from=farmer-addons g2p_rest_api/ /opt/bitnami/odoo/extraaddons/dad/g2p_rest_api/

USER odoo
