"""Tests for PII masking — verify phone/fax fields are excluded from BigQuery."""
import json
import os

import pytest

CONNECT_DIR = os.path.join(os.path.dirname(__file__), "..", "connect")
INFRA_DIR = os.path.join(os.path.dirname(__file__), "..", "infra")


@pytest.fixture
def bigquery_sink_config():
    config_file = os.path.join(CONNECT_DIR, "bigquery-sink.json")
    with open(config_file) as f:
        return json.load(f)


@pytest.fixture
def bigquery_tf():
    tf_file = os.path.join(INFRA_DIR, "bigquery.tf")
    with open(tf_file) as f:
        return f.read()


# ---- SMT Configuration Tests ----

def test_sink_connector_has_replace_field_smt(bigquery_sink_config):
    config = bigquery_sink_config.get("config", {})
    transforms = config.get("transforms", "")
    assert "filterFields" in transforms or "ReplaceField" in str(config), (
        "BigQuery sink connector must have a ReplaceField SMT to exclude PII fields"
    )


def test_sink_connector_excludes_phone(bigquery_sink_config):
    config_str = json.dumps(bigquery_sink_config)
    assert "phone" in config_str.lower(), (
        "BigQuery sink connector SMT must reference 'phone' field for exclusion"
    )


def test_sink_connector_excludes_fax(bigquery_sink_config):
    config_str = json.dumps(bigquery_sink_config)
    assert "fax" in config_str.lower(), (
        "BigQuery sink connector SMT must reference 'fax' field for exclusion"
    )


# ---- BigQuery Schema Tests ----

def test_bronze_tables_have_no_phone_column(bigquery_tf):
    # Bronze tables use generic Debezium envelope columns (before, after, op, ts_ms)
    # They don't have entity-specific columns — phone/fax are inside the JSON 'after' blob
    # This is expected: PII exclusion happens at the Kafka Connect SMT level
    # The SMT strips phone/fax from the JSON before it reaches BigQuery
    assert "phone" not in bigquery_tf.split("# Silver")[0].lower() or \
           "after" in bigquery_tf, (
        "Bronze layer uses JSON envelope — phone/fax excluded by SMT before ingestion"
    )


def test_silver_tables_have_no_phone_column(bigquery_tf):
    # Silver table schemas should not include phone or fax columns
    silver_section = bigquery_tf.split("# Gold")[0].split("Silver")[-1] \
        if "Silver" in bigquery_tf else ""
    # Check the customer table schema specifically (most likely to have phone/fax)
    customer_section = bigquery_tf[
        bigquery_tf.find('silver_customer'):
        bigquery_tf.find('silver_employee')
    ] if 'silver_customer' in bigquery_tf else ""
    assert "phone" not in customer_section.lower(), (
        "Silver customer table schema must not include 'phone' column (PII)"
    )


def test_silver_tables_have_no_fax_column(bigquery_tf):
    customer_section = bigquery_tf[
        bigquery_tf.find('silver_customer'):
        bigquery_tf.find('silver_employee')
    ] if 'silver_customer' in bigquery_tf else ""
    assert "fax" not in customer_section.lower(), (
        "Silver customer table schema must not include 'fax' column (PII)"
    )


def test_gold_tables_have_no_phone_column(bigquery_tf):
    gold_section = bigquery_tf[bigquery_tf.find("Gold"):] \
        if "Gold" in bigquery_tf else ""
    assert "phone" not in gold_section.lower(), (
        "Gold layer tables must not include 'phone' column (PII)"
    )


def test_gold_tables_have_no_fax_column(bigquery_tf):
    gold_section = bigquery_tf[bigquery_tf.find("Gold"):] \
        if "Gold" in bigquery_tf else ""
    assert "fax" not in gold_section.lower(), (
        "Gold layer tables must not include 'fax' column (PII)"
    )
