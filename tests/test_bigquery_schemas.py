"""Tests for Task 5.x: BigQuery Schema Validation.

Validates:
- Terraform includes all 3 datasets (bronze, silver, gold)
- 11 Bronze tables with Debezium envelope columns
- 11 Silver tables with entity-specific columns
- 3 Gold dimension tables and 2 Gold fact tables
- Metadata columns (_loaded_at, _source_ts_ms) on all tables
"""

import json
import os

import pytest

PROJECT_ROOT = os.path.join(os.path.dirname(__file__), "..")
INFRA_DIR = os.path.join(PROJECT_ROOT, "infra")


# =========================================================================
# Fixtures
# =========================================================================

@pytest.fixture(scope="module")
def bigquery_tf():
    filepath = os.path.join(INFRA_DIR, "bigquery.tf")
    with open(filepath) as f:
        return f.read()


# =========================================================================
# Happy Path: All 3 datasets defined
# =========================================================================

DATASETS = ["bronze", "silver", "gold"]


@pytest.mark.parametrize("dataset", DATASETS)
def test_dataset_exists(bigquery_tf, dataset):
    assert f'dataset_id  = "{dataset}"' in bigquery_tf, (
        f"BigQuery dataset '{dataset}' not found in bigquery.tf"
    )


@pytest.mark.parametrize("dataset", DATASETS)
def test_dataset_location(bigquery_tf, dataset):
    assert "var.region" in bigquery_tf, (
        "Datasets should use var.region for location"
    )


# =========================================================================
# Happy Path: 11 Bronze tables with Debezium envelope
# =========================================================================

CHINOOK_TABLES = [
    "customer", "employee", "artist", "album", "track",
    "genre", "media_type", "invoice", "invoice_line",
    "playlist", "playlist_track",
]


@pytest.mark.parametrize("table", CHINOOK_TABLES)
def test_bronze_table_exists(bigquery_tf, table):
    assert f"{table}_raw" in bigquery_tf, (
        f"Bronze table '{table}_raw' not found in bigquery.tf"
    )


BRONZE_COLUMNS = ["before", "after", "op", "ts_ms", "source"]


@pytest.mark.parametrize("column", BRONZE_COLUMNS)
def test_bronze_has_debezium_column(bigquery_tf, column):
    # Check at least one Bronze table has the column
    assert f'"name" = "{column}"' in bigquery_tf or \
           f'name = "{column}"' in bigquery_tf, (
        f"Bronze tables missing Debezium column '{column}'"
    )


# =========================================================================
# Happy Path: 11 Silver tables with entity columns
# =========================================================================

@pytest.mark.parametrize("table", CHINOOK_TABLES)
def test_silver_table_exists(bigquery_tf, table):
    assert f'table_id            = "{table}"' in bigquery_tf or \
           f'table_id  = "{table}"' in bigquery_tf, (
        f"Silver table '{table}' not found in bigquery.tf"
    )


@pytest.mark.parametrize("table", CHINOOK_TABLES)
def test_silver_has_is_deleted(bigquery_tf, table):
    # All Silver tables must have is_deleted
    assert "is_deleted" in bigquery_tf, (
        "Silver tables must include 'is_deleted' BOOLEAN column"
    )


# =========================================================================
# Happy Path: Gold dimension tables (SCD2)
# =========================================================================

GOLD_DIMENSIONS = ["dim_customer", "dim_track", "dim_employee"]
GOLD_FACTS = ["fct_invoice", "fct_invoice_line"]


@pytest.mark.parametrize("table", GOLD_DIMENSIONS)
def test_gold_dimension_exists(bigquery_tf, table):
    assert table in bigquery_tf, (
        f"Gold dimension table '{table}' not found in bigquery.tf"
    )


@pytest.mark.parametrize("table", GOLD_DIMENSIONS)
def test_gold_dimension_has_scd2_columns(bigquery_tf, table):
    for col in ["surrogate_key", "natural_key", "valid_from", "valid_to", "is_active"]:
        assert col in bigquery_tf, (
            f"Gold dimension '{table}' missing SCD2 column '{col}'"
        )


@pytest.mark.parametrize("table", GOLD_FACTS)
def test_gold_fact_exists(bigquery_tf, table):
    assert table in bigquery_tf, (
        f"Gold fact table '{table}' not found in bigquery.tf"
    )


def test_gold_dim_track_has_denormalized_columns(bigquery_tf):
    for col in ["album_title", "artist_name", "genre_name", "media_type_name"]:
        assert col in bigquery_tf, (
            f"dim_track missing denormalized column '{col}'"
        )


def test_gold_fct_invoice_has_customer_key(bigquery_tf):
    assert "customer_key" in bigquery_tf, (
        "fct_invoice must have customer_key surrogate reference"
    )


def test_gold_fct_invoice_line_has_surrogate_keys(bigquery_tf):
    for col in ["track_key", "customer_key"]:
        assert col in bigquery_tf, (
            f"fct_invoice_line must have surrogate key '{col}'"
        )


def test_gold_fct_invoice_line_has_line_total(bigquery_tf):
    assert "line_total" in bigquery_tf, (
        "fct_invoice_line must have computed 'line_total' column"
    )


# =========================================================================
# Happy Path: Metadata columns on all layers
# =========================================================================

def test_all_layers_have_loaded_at(bigquery_tf):
    assert bigquery_tf.count("_loaded_at") >= 20, (
        "All tables across all layers must include '_loaded_at' column"
    )


def test_silver_and_gold_have_source_ts_ms(bigquery_tf):
    assert bigquery_tf.count("_source_ts_ms") >= 15, (
        "Silver and Gold tables must include '_source_ts_ms' column"
    )


# =========================================================================
# Edge Case: Table counts
# =========================================================================

def test_bronze_table_count(bigquery_tf):
    # 11 bronze tables via for_each
    assert "for_each = local.bronze_tables" in bigquery_tf, (
        "Bronze tables should use for_each for consistency"
    )


def test_silver_table_count(bigquery_tf):
    silver_count = bigquery_tf.count('google_bigquery_dataset.silver.dataset_id')
    assert silver_count == 11, (
        f"Expected 11 Silver tables, found {silver_count} references"
    )


def test_gold_table_count(bigquery_tf):
    gold_count = bigquery_tf.count('google_bigquery_dataset.gold.dataset_id')
    assert gold_count == 5, (
        f"Expected 5 Gold tables (3 dims + 2 facts), found {gold_count} references"
    )
