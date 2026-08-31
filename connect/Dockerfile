# =============================================================================
# Kafka Connect Docker Image (Source Only)
# =============================================================================
# Custom Kafka Connect image with:
# - Debezium PostgreSQL Source Connector
# - Google Managed Kafka auth library (GcpLoginCallbackHandler)
#
# Used when source_connector_type = "cloudrun" to run the CDC source
# connector on Cloud Run instead of the built-in managed connector.
#
# The BigQuery and GCS sinks are always handled by Managed Kafka Connect
# and do NOT need to be included in this image.
#
# Build:
#   gcloud builds submit connect/ \
#     --tag=<region>-docker.pkg.dev/<project>/cdc-demo-docker/kafka-connect:latest
# =============================================================================

FROM confluentinc/cp-kafka-connect:7.7.1

# Connector versions
ENV DEBEZIUM_VERSION=2.5.4.Final
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
# Install Google Managed Kafka Auth Library
# (Provides GcpLoginCallbackHandler for OAUTHBEARER authentication)
# -----------------------------------------------------------------------------
RUN mkdir -p /tmp/gmk-auth /etc/kafka-connect/jars/ && \
    curl -sL "https://github.com/googleapis/managedkafka/releases/download/v${MANAGED_KAFKA_AUTH_VERSION}/release-and-dependencies.zip" \
      -o /tmp/gmk-auth/release.zip && \
    python3 -c "import zipfile,os; z=zipfile.ZipFile('/tmp/gmk-auth/release.zip'); [open('/etc/kafka-connect/jars/'+os.path.basename(n),'wb').write(z.read(n)) for n in z.namelist() if not n.endswith('/')]" && \
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
ENV CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE="true"
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
