# WSO2 MI custom image.
#
# This Dockerfile re-tags the official WSO2 MI image into the private registry,
# fixes the entrypoint execute bit (Docker Hub layer recompression can strip it),
# and embeds CAR artifacts staged into docker/carbonapps/.
#
# build-images.sh prepares the official currency converter sample CAR automatically
# before the docker build runs.
#
# Build example (build context = docker/):
#   docker build --build-arg BASE_IMAGE=docker.wso2.com/wso2mi:4.5.0.16-alpine \
#                -f docker/mi.Dockerfile -t <registry>/<repo>:<tag> docker/

ARG BASE_IMAGE=docker.wso2.com/wso2mi:4.5.0.16-alpine
FROM ${BASE_IMAGE}

USER root

# Ensure the entrypoint is executable (Docker Hub layer recompression can strip the execute bit).
RUN chmod +x /home/wso2carbon/docker-entrypoint.sh

# The 4.5.0.16 image tag still installs MI under the 4.5.0 server home.
ARG WSO2_SERVER_HOME=/home/wso2carbon/wso2mi-4.5.0
COPY --chown=wso2carbon:wso2 carbonapps/ ${WSO2_SERVER_HOME}/repository/deployment/server/carbonapps/

USER wso2carbon
