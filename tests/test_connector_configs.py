"""Tests for Task 4.x: Kafka Connect Connector Configurations.

Validates:
- JSON syntax of connector config files
- Required fields are present in both configs
- SMT configuration excludes phone and fax
- Topic regex matches expected Debezium topic names
- Registration script structure
"""

import json
import os
import re

import pytest

PROJECT_ROOT = os.path.join(os.path.dirname(__file__), "..")
CONNECT_DIR = os.path.join(PROJECT_ROOT, "connect")


# =========================================================================
# Fixtures
# =========================================================================

@pytest.fixture(scope="module")
def source_config():
    filepath = os.path.join(CONNECT_DIR, "debezium-source.json")
    with open(filepath) as f:
        return json.load(f)


@pytest.fixture(scope="module")
def sink_config():
    filepath = os.path.join(CONNECT_DIR, "bigquery-sink.json")
    with open(filepath) as f:
        return json.load(f)


@pytest.fixture(scope="module")
def register_script():
    filepath = os.path.join(CONNECT_DIR, "register-connectors.sh")
    with open(filepath) as f:
        return f.read()


# =========================================================================
# Happy Path: JSON files are valid and parseable
# =========================================================================

def test_source_config_is_valid_json():
    filepath = os.path.join(CONNECT_DIR, "debezium-source.json")
    with open(filepath) as f:
        data = json.load(f)
    assert "name" in data, "Source config must have a 'name' field"
    assert "config" in data, "Source config must have a 'config' field"


def test_sink_config_is_valid_json():
    filepath = os.path.join(CONNECT_DIR, "bigquery-sink.json")
    with open(filepath) as f:
        data = json.load(f)
    assert "name" in data, "Sink config must have a 'name' field"
    assert "config" in data, "Sink config must have a 'config' field"


# =========================================================================
# Happy Path: Debezium Source required fields
# =========================================================================

DEBEZIUM_REQUIRED_FIELDS = [
    "connector.class",
    "database.hostname",
    "database.port",
    "database.user",
    "database.password",
    "database.dbname",
    "topic.prefix",
    "table.include.list",
    "plugin.name",
    "slot.name",
    "publication.name",
]


@pytest.mark.parametrize("field", DEBEZIUM_REQUIRED_FIELDS)
def test_source_has_required_field(source_config, field):
    assert field in source_config["config"], (
        f"Debezium source config missing required field '{field}'"
    )


def test_source_connector_class(source_config):
    assert source_config["config"]["connector.class"] == \
        "io.debezium.connector.postgresql.PostgresConnector", (
        "Source connector must use Debezium PostgreSQL connector class"
    )


def test_source_uses_pgoutput(source_config):
    assert source_config["config"]["plugin.name"] == "pgoutput", (
        "Source must use pgoutput plugin for logical decoding"
    )


def test_source_uses_debezium_slot(source_config):
    assert source_config["config"]["slot.name"] == "debezium_slot", (
        "Source must use the debezium_slot replication slot"
    )


def test_source_uses_json_converter(source_config):
    config = source_config["config"]
    assert config["key.converter"] == \
        "org.apache.kafka.connect.json.JsonConverter", (
        "Source must use JSON key converter"
    )
    assert config["value.converter"] == \
        "org.apache.kafka.connect.json.JsonConverter", (
        "Source must use JSON value converter"
    )


# =========================================================================
# Happy Path: BigQuery Sink required fields
# =========================================================================

BIGQUERY_REQUIRED_FIELDS = [
    "connector.class",
    "topics.regex",
    "project",
    "defaultDataset",
]


@pytest.mark.parametrize("field", BIGQUERY_REQUIRED_FIELDS)
def test_sink_has_required_field(sink_config, field):
    assert field in sink_config["config"], (
        f"BigQuery sink config missing required field '{field}'"
    )


def test_sink_connector_class(sink_config):
    assert "BigQuerySinkConnector" in sink_config["config"]["connector.class"], (
        "Sink connector must use BigQuerySinkConnector class"
    )


# =========================================================================
# Happy Path: Topic regex matches Debezium naming
# =========================================================================

def test_sink_topic_regex_matches_debezium_topics(sink_config):
    regex = sink_config["config"]["topics.regex"]
    # The regex should match all chinook.public.* topics
    compiled = re.compile(regex)
    tables = [
        "customer", "employee", "artist", "album", "track",
        "genre", "media_type", "invoice", "invoice_line",
        "playlist", "playlist_track",
    ]
    for table in tables:
        topic = f"chinook.public.{table}"
        assert compiled.match(topic), (
            f"topics.regex '{regex}' does not match topic '{topic}'"
        )


def test_sink_topic_regex_does_not_match_unrelated(sink_config):
    regex = sink_config["config"]["topics.regex"]
    compiled = re.compile(regex)
    assert not compiled.match("other.schema.table"), (
        f"topics.regex '{regex}' should not match unrelated topics"
    )


# =========================================================================
# Happy Path: SMT configuration
# =========================================================================

def test_sink_has_smt_transforms(sink_config):
    config = sink_config["config"]
    assert "transforms" in config, (
        "Sink config must include SMT transforms"
    )


def test_sink_smt_excludes_phone_and_fax(sink_config):
    config = sink_config["config"]
    # Find the ReplaceField SMT
    exclude_field = None
    for key, value in config.items():
        if key.endswith(".exclude"):
            exclude_field = value
            break

    assert exclude_field is not None, (
        "Sink config must have a ReplaceField SMT with 'exclude' property"
    )
    assert "phone" in exclude_field, (
        f"SMT exclude must include 'phone', got: {exclude_field}"
    )
    assert "fax" in exclude_field, (
        f"SMT exclude must include 'fax', got: {exclude_field}"
    )


def test_sink_smt_filters_tombstones(sink_config):
    config = sink_config["config"]
    transforms = config.get("transforms", "")
    has_tombstone_filter = False
    for key, value in config.items():
        if "RecordIsTombstone" in str(value):
            has_tombstone_filter = True
            break
    assert has_tombstone_filter, (
        "Sink config must include a tombstone record filter"
    )


# =========================================================================
# Happy Path: Auth configuration for Google Managed Kafka
# =========================================================================

def test_source_has_oauthbearer_auth(source_config):
    config = source_config["config"]
    auth_keys = [k for k in config if "sasl.mechanism" in k]
    assert any("OAUTHBEARER" in config[k] for k in auth_keys), (
        "Source must configure OAUTHBEARER authentication"
    )


def test_sink_has_oauthbearer_auth(sink_config):
    config = sink_config["config"]
    auth_keys = [k for k in config if "sasl.mechanism" in k]
    assert any("OAUTHBEARER" in config[k] for k in auth_keys), (
        "Sink must configure OAUTHBEARER authentication"
    )


# =========================================================================
# Edge Case: Registration script structure
# =========================================================================

def test_register_script_exists():
    filepath = os.path.join(CONNECT_DIR, "register-connectors.sh")
    assert os.path.isfile(filepath), "register-connectors.sh must exist"
    assert os.access(filepath, os.X_OK), "register-connectors.sh must be executable"


def test_register_script_has_health_check(register_script):
    assert "/connectors" in register_script, (
        "register-connectors.sh must call the connectors REST API"
    )


def test_register_script_has_retry_logic(register_script):
    assert "retry" in register_script.lower() or "attempt" in register_script.lower(), (
        "register-connectors.sh must include retry logic"
    )


def test_register_script_has_error_handling(register_script):
    assert "set -euo pipefail" in register_script, (
        "register-connectors.sh must use strict error handling"
    )


def test_register_script_has_timestamped_logging(register_script):
    assert "date -u" in register_script, (
        "register-connectors.sh must include timestamped logging"
    )
