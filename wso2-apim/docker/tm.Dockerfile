ARG BASE_IMAGE=docker.wso2.com/wso2am-tm:4.6.0
FROM ${BASE_IMAGE}

ARG POSTGRES_JDBC_VERSION=42.7.4

# Add PostgreSQL JDBC driver required for external PostgreSQL databases.
# Uses find to locate the server home so this works across any image tag.
USER root
RUN set -eu; \
    server_home="$(find /home/wso2carbon -maxdepth 1 -name 'wso2am-tm*' -type d | sort | head -1)"; \
    lib_dir="${server_home}/repository/components/lib"; \
    wget -q -O "${lib_dir}/postgresql-${POSTGRES_JDBC_VERSION}.jar" \
         "https://jdbc.postgresql.org/download/postgresql-${POSTGRES_JDBC_VERSION}.jar"; \
    chown wso2carbon:wso2 "${lib_dir}/postgresql-${POSTGRES_JDBC_VERSION}.jar"
USER wso2carbon
