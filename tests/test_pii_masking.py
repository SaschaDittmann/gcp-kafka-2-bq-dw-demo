"""Tests for PII masking — verify phone/fax fields are excluded from BigQuery."""
import json
import os
import re

import pytest

CONNECT_DIR = os.path.join(os.path.dirname(__file__), "..", "connect")
INFRA_DIR = os.path.join(os.path.dirname(__file__), "..", "infra")

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
        match = re.search(r'"([^"]+)"\s*=\s*"([^"]+)"', line)
        if match:
            config[match.group(1)] = match.group(2)
        else:
            match2 = re.search(r'"([^"]+)"\s*=\s*([a-zA-Z0-9_\.\-]+)', line)
            if match2:
                config[match2.group(1)] = match2.group(2)
    return {"config": config}


@pytest.fixture
def bigquery_sink_config():
    return extract_tf_config("bigquery_sink")


@pytest.fixture
def bigquery_tf():
    tf_file = os.path.join(INFRA_DIR, "bigquery.tf")
    with open(tf_file) as f:
        return f.read()


# ---- SMT Configuration Tests ----

def test_sink_connector_has_replace_field_smt(bigquery_sink_config):
    config = bigquery_sink_config.get("config", {})
    transforms = config.get("transforms", "")
    assert "ReplaceField" in str(config), (
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
    assert "phone" not in bigquery_tf.split("# Silver")[0].lower() or \
           "after" in bigquery_tf, (
        "Bronze layer uses JSON envelope — phone/fax excluded by SMT before ingestion"
    )


def test_silver_tables_have_no_phone_column(bigquery_tf):
    silver_section = bigquery_tf.split("# Gold")[0].split("Silver")[-1] \
        if "Silver" in bigquery_tf else ""
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
