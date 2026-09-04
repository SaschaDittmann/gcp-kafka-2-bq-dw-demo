"""Tests for Task 4.x: Kafka Connect Connector Configurations.

Validates:
- JSON syntax of connector config files (if any exist)
- Required fields are present in configs
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
INFRA_DIR = os.path.join(PROJECT_ROOT, "infra")

def extract_tf_config(resource_id):
    filepath = os.path.join(INFRA_DIR, "kafka_connect.tf")
    if not os.path.exists(filepath):
        return {}
    with open(filepath) as f:
        content = f.read()

    resource_pattern = f'resource "google_managed_kafka_connector" "{resource_id}" {{'
    start_idx = content.find(resource_pattern)
    if start_idx == -1:
        return {}

    configs_start = content.find('configs = {', start_idx)
    if configs_start == -1:
        return {}

    configs_end = content.find('}', configs_start)
    configs_block = content[configs_start:configs_end]

    config = {}
    for line in configs_block.split('\n'):
        # parse "key" = "value"
        match = re.search(r'"([^"]+)"\s*=\s*"([^"]+)"', line)
        if match:
            config[match.group(1)] = match.group(2)
        else:
            # parse "key" = variable (like true/false or var.project_id)
            match2 = re.search(r'"([^"]+)"\s*=\s*([a-zA-Z0-9_\.\-]+)', line)
            if match2:
                config[match2.group(1)] = match2.group(2)
    return {"config": config}

@pytest.fixture(scope="module")
def source_config():
    filepath = os.path.join(CONNECT_DIR, "debezium-source.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return extract_tf_config('cdc_source')

@pytest.fixture(scope="module")
def sink_config():
    return extract_tf_config('bigquery_sink')

@pytest.fixture(scope="module")
def register_script():
    filepath = os.path.join(CONNECT_DIR, "register-connectors.sh")
    with open(filepath) as f:
        return f.read()

def test_source_config_is_valid_json():
    filepath = os.path.join(CONNECT_DIR, "debezium-source.json")
    if not os.path.exists(filepath):
        pytest.skip("debezium-source.json not used in managed mode")
    with open(filepath) as f:
        data = json.load(f)
    assert "name" in data, "Source config must have a 'name' field"
    assert "config" in data, "Source config must have a 'config' field"

def test_sink_config_is_valid_json():
    filepath = os.path.join(CONNECT_DIR, "bigquery-sink.json")
    if not os.path.exists(filepath):
        pytest.skip("bigquery-sink.json not used in managed mode")

DEBEZIUM_REQUIRED_FIELDS = [
    "connector.class",
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
    assert "PostgresConnector" in source_config["config"]["connector.class"], (
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
    assert "JsonConverter" in config["key.converter"], (
        "Source must use JSON key converter"
    )
    assert "JsonConverter" in config["value.converter"], (
        "Source must use JSON value converter"
    )

def test_source_schemas_enable_is_true(source_config):
    """BQ sink requires embedded Debezium schema for type inference."""
    config = source_config["config"]
    assert config.get("value.converter.schemas.enable") == "true", (
        "value.converter.schemas.enable must be 'true' — "
        "the BigQuery sink needs embedded schema for table creation"
    )

def test_source_topic_prefix_is_cdc(source_config):
    """Topic prefix must be 'cdc' to match the BQ sink topics.regex."""
    config = source_config["config"]
    assert config["topic.prefix"] == "cdc", (
        "topic.prefix must be 'cdc' to match sink regex 'cdc\\.public\\..*'"
    )

BIGQUERY_REQUIRED_FIELDS = [
    "connector.class",
    "topics.regex",
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

def test_sink_topic_regex_matches_debezium_topics(sink_config):
    # Regex read from TF file includes the backslash escapes
    # "cdc\\.public\\..*" -> cdc\.public\..*
    regex = sink_config["config"]["topics.regex"].replace('\\\\', '\\')
    compiled = re.compile(regex)
    tables = [
        "customer", "employee", "artist", "album", "track",
        "genre", "media_type", "invoice", "invoice_line",
        "playlist", "playlist_track",
    ]
    for table in tables:
        topic = f"cdc.public.{table}"
        assert compiled.match(topic), (
            f"topics.regex '{regex}' does not match topic '{topic}'"
        )

def test_sink_topic_regex_does_not_match_unrelated(sink_config):
    regex = sink_config["config"]["topics.regex"].replace('\\\\', '\\')
    compiled = re.compile(regex)
    assert not compiled.match("other.schema.table"), (
        f"topics.regex '{regex}' should not match unrelated topics"
    )

def test_sink_has_smt_transforms(sink_config):
    config = sink_config["config"]
    assert "transforms" in config, (
        "Sink config must include SMT transforms"
    )

def test_sink_smt_excludes_phone_and_fax(sink_config):
    config = sink_config["config"]
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
    has_tombstone_filter = False
    for key, value in config.items():
        if "RecordIsTombstone" in str(value):
            has_tombstone_filter = True
            break
    assert has_tombstone_filter, (
        "Sink config must include a tombstone record filter"
    )

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
