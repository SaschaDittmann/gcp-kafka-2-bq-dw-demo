# =============================================================================
# Kafka Connect Docker Image (Source Only)
# =============================================================================
# Custom Kafka Connect image based on the official Debezium Connect image
# which includes the PostgreSQL CDC connector out of the box.
#
# Only the Google Managed Kafka auth library needs to be added for
# SASL/OAUTHBEARER authentication to GCP Managed Kafka.
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

FROM debezium/connect:2.5

ENV MANAGED_KAFKA_AUTH_VERSION=1.0.6

# -----------------------------------------------------------------------------
# Install Google Managed Kafka Auth Library
# (Provides GcpLoginCallbackHandler for OAUTHBEARER authentication)
# Installed to /kafka/libs/ so it's on the Kafka classpath for both
# the Connect worker and any startup scripts.
# -----------------------------------------------------------------------------
USER root
RUN mkdir -p /tmp/gmk-auth && \
    curl -sL "https://github.com/googleapis/managedkafka/releases/download/v${MANAGED_KAFKA_AUTH_VERSION}/release-and-dependencies.zip" \
      -o /tmp/gmk-auth/release.zip && \
    python3 -c "import zipfile,os; z=zipfile.ZipFile('/tmp/gmk-auth/release.zip'); [open('/kafka/libs/'+os.path.basename(n),'wb').write(z.read(n)) for n in z.namelist() if not n.endswith('/')]" && \
    rm -rf /tmp/gmk-auth
USER kafka

EXPOSE 8083
