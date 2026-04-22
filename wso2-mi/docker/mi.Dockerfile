# WSO2 MI custom image.
#
# This Dockerfile re-tags the official WSO2 MI image into the private registry and
# fixes the entrypoint execute bit (Docker Hub layer recompression can strip it).
#
# To embed integration CAR artifacts, copy them into docker/carbonapps/ and
# uncomment the COPY block below before running `make deploy`. CARs are built by:
#
#   wget https://mi.docs.wso2.com/en/4.5.0/assets/attachments/install-and-setup/currencyconverter.zip
#   unzip currencyconverter.zip && cd currencyconverter && mvn clean install -Pdocker
#   cp target/CurrencyConverter*.car ../carbonapps/
#
# Build example (build context = docker/):
#   docker build --build-arg BASE_IMAGE=docker.wso2.com/wso2mi:4.5.0.16-alpine \
#                -f docker/mi.Dockerfile -t <registry>/<repo>:<tag> docker/

ARG BASE_IMAGE=docker.wso2.com/wso2mi:4.5.0.16-alpine
FROM ${BASE_IMAGE}

USER root

# Ensure the entrypoint is executable (Docker Hub layer recompression can strip the execute bit).
RUN chmod +x /home/wso2carbon/docker-entrypoint.sh

# Uncomment to embed CAR artifacts (place .car files into docker/carbonapps/ first):
# ARG WSO2_SERVER_HOME=/home/wso2carbon/wso2mi-4.5.0.16
# COPY --chown=wso2carbon:wso2 carbonapps/ ${WSO2_SERVER_HOME}/repository/deployment/server/carbonapps/

USER wso2carbon
