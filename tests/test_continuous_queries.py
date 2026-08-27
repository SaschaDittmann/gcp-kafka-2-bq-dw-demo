"""Tests for Task 5.x: Continuous Query SQL Validation.

Validates:
- All CQ SQL scripts exist in transform/
- Each CQ references the correct source and target tables
- SQL uses INSERT INTO ... SELECT FROM APPENDS() pattern
- dim_track CQ joins album, artist, genre, and media_type
- Fact CQs reference dimension surrogate keys
"""

import os
import re

import pytest

PROJECT_ROOT = os.path.join(os.path.dirname(__file__), "..")
TRANSFORM_DIR = os.path.join(PROJECT_ROOT, "transform")


# =========================================================================
# Fixtures
# =========================================================================

def load_sql(filename):
    filepath = os.path.join(TRANSFORM_DIR, filename)
    with open(filepath) as f:
        return f.read()


# =========================================================================
# Happy Path: All Silver CQ scripts exist
# =========================================================================

SILVER_CQ_FILES = [
    "silver_customer.sql",
    "silver_employee.sql",
    "silver_track.sql",
    "silver_invoice.sql",
    "silver_invoice_line.sql",
]

# Reference/lookup tables use views on Bronze (no CQ scripts needed):
# artist, album, genre, media_type, playlist, playlist_track


@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_file_exists(filename):
    filepath = os.path.join(TRANSFORM_DIR, filename)
    assert os.path.isfile(filepath), f"Missing CQ script: {filename}"


# =========================================================================
# Happy Path: All Gold CQ scripts exist
# =========================================================================

GOLD_CQ_FILES = [
    "gold_dim_customer.sql",
    "gold_dim_track.sql",
    "gold_dim_employee.sql",
    "gold_fct_invoice.sql",
    "gold_fct_invoice_line.sql",
]


@pytest.mark.parametrize("filename", GOLD_CQ_FILES)
def test_gold_cq_file_exists(filename):
    filepath = os.path.join(TRANSFORM_DIR, filename)
    assert os.path.isfile(filepath), f"Missing CQ script: {filename}"


# =========================================================================
# Happy Path: Silver CQs use correct source/target tables
# =========================================================================

SILVER_CQ_TABLE_MAP = {
    "silver_customer.sql":       ("bronze.customer_raw",       "silver.customer"),
    "silver_employee.sql":       ("bronze.employee_raw",       "silver.employee"),
    "silver_track.sql":          ("bronze.track_raw",          "silver.track"),
    "silver_invoice.sql":        ("bronze.invoice_raw",        "silver.invoice"),
    "silver_invoice_line.sql":   ("bronze.invoice_line_raw",   "silver.invoice_line"),
}


@pytest.mark.parametrize("filename,tables", SILVER_CQ_TABLE_MAP.items())
def test_silver_cq_source_and_target(filename, tables):
    sql = load_sql(filename)
    source, target = tables
    assert source in sql, (
        f"{filename} must read from {source}"
    )
    assert target in sql, (
        f"{filename} must write to {target}"
    )


# =========================================================================
# Happy Path: All CQs use INSERT INTO ... APPENDS() pattern
# =========================================================================

ALL_CQ_FILES = SILVER_CQ_FILES + GOLD_CQ_FILES


@pytest.mark.parametrize("filename", ALL_CQ_FILES)
def test_cq_uses_insert_into(filename):
    sql = load_sql(filename)
    assert "INSERT INTO" in sql.upper(), (
        f"{filename} must use INSERT INTO pattern"
    )


@pytest.mark.parametrize("filename", ALL_CQ_FILES)
def test_cq_uses_appends(filename):
    sql = load_sql(filename)
    assert "APPENDS(" in sql.upper() or "APPENDS(" in sql, (
        f"{filename} must use APPENDS() table-valued function"
    )


# =========================================================================
# Happy Path: Silver CQs extract from JSON 'after' payload
# =========================================================================

@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_uses_json_value(filename):
    sql = load_sql(filename)
    assert "JSON_VALUE(after" in sql, (
        f"{filename} must extract fields from 'after' JSON payload"
    )


# =========================================================================
# Happy Path: Silver CQs handle deletes
# =========================================================================

@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_handles_deletes(filename):
    sql = load_sql(filename)
    assert "is_deleted" in sql, (
        f"{filename} must set is_deleted flag"
    )
    assert "op = 'd'" in sql or "op = \\'d\\'" in sql, (
        f"{filename} must check for delete operations"
    )


# =========================================================================
# Happy Path: Silver CQs include metadata columns
# =========================================================================

@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_has_loaded_at(filename):
    sql = load_sql(filename)
    assert "_loaded_at" in sql, f"{filename} must include _loaded_at"
    assert "_CHANGE_TIMESTAMP" in sql, f"{filename} must use _CHANGE_TIMESTAMP"


@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_has_source_ts_ms(filename):
    sql = load_sql(filename)
    assert "_source_ts_ms" in sql, f"{filename} must include _source_ts_ms"


# =========================================================================
# Happy Path: dim_track denormalization
# =========================================================================

def test_dim_track_joins_album():
    sql = load_sql("gold_dim_track.sql")
    assert "silver.album" in sql, (
        "dim_track CQ must reference silver.album"
    )


def test_dim_track_joins_artist():
    sql = load_sql("gold_dim_track.sql")
    assert "silver.artist" in sql, (
        "dim_track CQ must reference silver.artist"
    )


def test_dim_track_joins_genre():
    sql = load_sql("gold_dim_track.sql")
    assert "silver.genre" in sql, (
        "dim_track CQ must reference silver.genre"
    )


def test_dim_track_joins_media_type():
    sql = load_sql("gold_dim_track.sql")
    assert "silver.media_type" in sql, (
        "dim_track CQ must reference silver.media_type"
    )


# =========================================================================
# Happy Path: Gold dimensions use SCD2 pattern
# =========================================================================

GOLD_DIM_FILES = [
    "gold_dim_customer.sql",
    "gold_dim_track.sql",
    "gold_dim_employee.sql",
]


@pytest.mark.parametrize("filename", GOLD_DIM_FILES)
def test_gold_dim_generates_surrogate_key(filename):
    sql = load_sql(filename)
    assert "GENERATE_UUID()" in sql, (
        f"{filename} must generate surrogate keys with GENERATE_UUID()"
    )


@pytest.mark.parametrize("filename", GOLD_DIM_FILES)
def test_gold_dim_sets_is_active(filename):
    sql = load_sql(filename)
    assert "is_active" in sql, (
        f"{filename} must set is_active flag"
    )


# =========================================================================
# Happy Path: Fact CQs reference dimension keys
# =========================================================================

def test_fct_invoice_references_dim_customer():
    sql = load_sql("gold_fct_invoice.sql")
    assert "dim_customer" in sql, (
        "fct_invoice must reference dim_customer for surrogate key"
    )


def test_fct_invoice_line_references_dim_track():
    sql = load_sql("gold_fct_invoice_line.sql")
    assert "dim_track" in sql, (
        "fct_invoice_line must reference dim_track for surrogate key"
    )


def test_fct_invoice_line_references_dim_customer():
    sql = load_sql("gold_fct_invoice_line.sql")
    assert "dim_customer" in sql, (
        "fct_invoice_line must reference dim_customer for surrogate key"
    )


def test_fct_invoice_line_computes_line_total():
    sql = load_sql("gold_fct_invoice_line.sql")
    assert "line_total" in sql, (
        "fct_invoice_line must compute line_total"
    )

