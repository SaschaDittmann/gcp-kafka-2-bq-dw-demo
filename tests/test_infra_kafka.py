"""Tests for Task 3.x: Google Managed Kafka Cluster & Topics.

Validates:
- Terraform configuration for Managed Kafka cluster and topics
- Topic naming convention matches Debezium defaults
- All 11 Chinook tables have corresponding topics
- Outputs include cluster and bootstrap information
"""

import os
import re

import pytest

PROJECT_ROOT = os.path.join(os.path.dirname(__file__), "..")
INFRA_DIR = os.path.join(PROJECT_ROOT, "infra")


# =========================================================================
# Fixtures
# =========================================================================

@pytest.fixture(scope="module")
def kafka_tf():
    filepath = os.path.join(INFRA_DIR, "kafka.tf")
    if not os.path.isfile(filepath):
        pytest.skip("kafka.tf not found")
    with open(filepath) as f:
        return f.read()


@pytest.fixture(scope="module")
def outputs_tf():
    filepath = os.path.join(INFRA_DIR, "outputs.tf")
    with open(filepath) as f:
        return f.read()


# =========================================================================
# Happy Path: Required files exist
# =========================================================================

def test_kafka_tf_exists():
    filepath = os.path.join(INFRA_DIR, "kafka.tf")
    assert os.path.isfile(filepath), "infra/kafka.tf must exist"


# =========================================================================
# Happy Path: Kafka cluster resource
# =========================================================================

def test_kafka_tf_contains_cluster_resource(kafka_tf):
    assert "google_managed_kafka_cluster" in kafka_tf, (
        "kafka.tf must contain a google_managed_kafka_cluster resource"
    )


def test_kafka_tf_configures_vpc(kafka_tf):
    assert "subnet" in kafka_tf.lower() or "vpc" in kafka_tf.lower(), (
        "kafka.tf must configure VPC/subnet connectivity"
    )


# =========================================================================
# Happy Path: All 11 Chinook tables have corresponding topics
# =========================================================================

EXPECTED_TABLES = [
    "customer", "employee", "artist", "album", "track",
    "genre", "media_type", "invoice", "invoice_line",
    "playlist", "playlist_track",
]


def test_kafka_tf_contains_topic_resource(kafka_tf):
    assert "google_managed_kafka_topic" in kafka_tf, (
        "kafka.tf must contain google_managed_kafka_topic resources"
    )


@pytest.mark.parametrize("table_name", EXPECTED_TABLES)
def test_kafka_tf_has_topic_for_table(kafka_tf, table_name):
    assert table_name in kafka_tf, (
        f"kafka.tf must define a topic for table '{table_name}'"
    )


def test_kafka_tf_uses_debezium_topic_naming(kafka_tf):
    pattern = r"cdc\.public\."
    assert re.search(pattern, kafka_tf), (
        "Topics must follow Debezium naming: 'cdc.public.<table>'"
    )


# =========================================================================
# Happy Path: Outputs include Kafka information
# =========================================================================

def test_outputs_include_kafka_cluster(outputs_tf):
    assert "kafka" in outputs_tf.lower(), (
        "outputs.tf must include Kafka cluster outputs"
    )


def test_outputs_include_bootstrap(outputs_tf):
    assert "bootstrap" in outputs_tf.lower(), (
        "outputs.tf must include bootstrap server endpoint"
    )


# =========================================================================
# Edge Case: Topic configuration
# =========================================================================

def test_kafka_tf_configures_partitions(kafka_tf):
    assert "partition" in kafka_tf.lower(), (
        "kafka.tf must configure topic partition count"
    )


def test_kafka_tf_configures_replication(kafka_tf):
    assert "replication" in kafka_tf.lower(), (
        "kafka.tf must configure topic replication factor"
    )


# =========================================================================
# Edge Case: Labels for observability
# =========================================================================

def test_kafka_tf_has_labels(kafka_tf):
    assert "labels" in kafka_tf or "common_labels" in kafka_tf, (
        "kafka.tf must include labels for observability"
    )

