# =============================================================================
# Kafka Connect Docker Image
# =============================================================================
# Custom Kafka Connect image with:
# - Debezium PostgreSQL Source Connector
# - BigQuery Kafka Sink Connector
# - Google Managed Kafka auth library (GcpLoginCallbackHandler)
#
# Build:
#   docker build -t kafka-connect-cdc connect/
#
# Run:
#   docker run -e CONNECT_BOOTSTRAP_SERVERS=... kafka-connect-cdc
# =============================================================================

FROM confluentinc/cp-kafka-connect:7.7.1

# Connector versions
ENV DEBEZIUM_VERSION=2.5.4.Final
ENV BQ_CONNECTOR_VERSION=2.14.0
ENV MANAGED_KAFKA_AUTH_VERSION=1.0.6

# -----------------------------------------------------------------------------
# Install Debezium PostgreSQL Source Connector (from Maven Central)
# confluent-hub can be unreliable for specific versions, so we download directly
# -----------------------------------------------------------------------------
RUN mkdir -p /usr/share/confluent-hub-components/debezium-connector-postgresql && \
    curl -sL "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/${DEBEZIUM_VERSION}/debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz" \
      -o /tmp/debezium.tar.gz && \
    tar -xzf /tmp/debezium.tar.gz -C /usr/share/confluent-hub-components/debezium-connector-postgresql/ && \
    rm /tmp/debezium.tar.gz

# -----------------------------------------------------------------------------
# Install BigQuery Sink Connector (from Aiven open-source fork)
# The original wepay connector is deprecated; Aiven maintains the active fork.
# confluent-hub is unreliable from Cloud Build, so we download directly.
# -----------------------------------------------------------------------------
RUN mkdir -p /usr/share/confluent-hub-components/bigquery-connector && \
    curl -sL "https://github.com/Aiven-Open/bigquery-connector-for-apache-kafka/releases/download/v${BQ_CONNECTOR_VERSION}/bigquery-connector-for-apache-kafka-${BQ_CONNECTOR_VERSION}.tar" \
      -o /tmp/bq-connector.tar && \
    tar -xf /tmp/bq-connector.tar -C /usr/share/confluent-hub-components/bigquery-connector/ && \
    rm /tmp/bq-connector.tar

# -----------------------------------------------------------------------------
# Install Google Managed Kafka Auth Library
# (Provides GcpLoginCallbackHandler for OAUTHBEARER authentication)
# -----------------------------------------------------------------------------
RUN mkdir -p /tmp/gmk-auth && \
    curl -sL "https://github.com/googleapis/managedkafka/releases/download/v${MANAGED_KAFKA_AUTH_VERSION}/release-and-dependencies.zip" \
      -o /tmp/gmk-auth/release.zip && \
    unzip -n -j /tmp/gmk-auth/release.zip -d /etc/kafka-connect/jars/ && \
    rm -rf /tmp/gmk-auth

# -----------------------------------------------------------------------------
# Kafka Connect worker configuration via environment variables
# These can be overridden at runtime (Cloud Run env vars or docker run -e)
# -----------------------------------------------------------------------------
ENV CONNECT_GROUP_ID="cdc-connect-group"
ENV CONNECT_CONFIG_STORAGE_TOPIC="connect-configs"
ENV CONNECT_OFFSET_STORAGE_TOPIC="connect-offsets"
ENV CONNECT_STATUS_STORAGE_TOPIC="connect-status"
ENV CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=3
ENV CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=3
ENV CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=3
ENV CONNECT_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter"
ENV CONNECT_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter"
ENV CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE="false"
ENV CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE="false"
ENV CONNECT_REST_PORT=8083
ENV CONNECT_PLUGIN_PATH="/usr/share/confluent-hub-components,/etc/kafka-connect/jars"

# Google Managed Kafka SASL/OAUTHBEARER auth for the Connect worker
ENV CONNECT_SECURITY_PROTOCOL="SASL_SSL"
ENV CONNECT_SASL_MECHANISM="OAUTHBEARER"
ENV CONNECT_SASL_LOGIN_CALLBACK_HANDLER_CLASS="com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler"
ENV CONNECT_SASL_JAAS_CONFIG="org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;"

# Producer/consumer also need SASL auth for internal topics
ENV CONNECT_PRODUCER_SECURITY_PROTOCOL="SASL_SSL"
ENV CONNECT_PRODUCER_SASL_MECHANISM="OAUTHBEARER"
ENV CONNECT_PRODUCER_SASL_LOGIN_CALLBACK_HANDLER_CLASS="com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler"
ENV CONNECT_PRODUCER_SASL_JAAS_CONFIG="org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;"
ENV CONNECT_CONSUMER_SECURITY_PROTOCOL="SASL_SSL"
ENV CONNECT_CONSUMER_SASL_MECHANISM="OAUTHBEARER"
ENV CONNECT_CONSUMER_SASL_LOGIN_CALLBACK_HANDLER_CLASS="com.google.cloud.hosted.kafka.auth.GcpLoginCallbackHandler"
ENV CONNECT_CONSUMER_SASL_JAAS_CONFIG="org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required;"

EXPOSE 8083
