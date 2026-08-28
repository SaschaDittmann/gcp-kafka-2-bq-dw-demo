"""Tests for Task 5.x: Transform SQL Validation.

Validates:
- All Silver CQ and Gold scheduled query SQL scripts exist in transform/
- Each script references the correct source and target tables
- Silver CQs use INSERT INTO ... SELECT FROM APPENDS() pattern
- Gold scheduled queries use INSERT INTO ... SELECT with time-windowed WHERE
- dim_track joins album, artist, genre, and media_type
- Fact queries reference dimension surrogate keys
- Gold current-state views exist
"""

import os

import pytest

PROJECT_ROOT = os.path.join(os.path.dirname(__file__), "..")
TRANSFORM_DIR = os.path.join(PROJECT_ROOT, "transform")


# =========================================================================
# Fixtures
# =========================================================================

def load_sql(filename):
    """Load a SQL file from the transform/ directory tree.

    Routes filenames to subfolders:
      silver_*.sql → silver/cq/  (strip silver_ prefix)
      gold_*.sql   → gold/sq/    (strip gold_ prefix)
    """
    if filename.startswith("silver_"):
        filepath = os.path.join(TRANSFORM_DIR, "silver", "cq", filename[len("silver_"):])
    elif filename.startswith("gold_"):
        filepath = os.path.join(TRANSFORM_DIR, "gold", "sq", filename[len("gold_"):])
    else:
        filepath = os.path.join(TRANSFORM_DIR, filename)
    with open(filepath) as f:
        return f.read()


# =========================================================================
# Happy Path: All Silver CQ scripts exist
# =========================================================================

SILVER_CQ_FILES = [
    "customer.sql",
    "employee.sql",
    "track.sql",
    "invoice.sql",
    "invoice_line.sql",
]

# Reference/lookup tables use views on Bronze (managed by Terraform in bigquery_views.tf):
# artist, album, genre, media_type, playlist, playlist_track

SILVER_VIEW_TABLE_IDS = [
    "artist",
    "album",
    "genre",
    "media_type",
    "playlist",
    "playlist_track",
]


@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_file_exists(filename):
    filepath = os.path.join(TRANSFORM_DIR, "silver", "cq", filename)
    assert os.path.isfile(filepath), f"Missing CQ script: silver/cq/{filename}"


INFRA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "infra")
VIEWS_TF = os.path.join(INFRA_DIR, "bigquery_views.tf")


@pytest.mark.parametrize("table_id", SILVER_VIEW_TABLE_IDS)
def test_silver_view_in_terraform(table_id):
    """Silver views are managed by Terraform in bigquery_views.tf."""
    assert os.path.isfile(VIEWS_TF), "Missing bigquery_views.tf"
    with open(VIEWS_TF) as f:
        content = f.read()
    assert f'table_id            = "{table_id}"' in content, (
        f"Silver view '{table_id}' not found in bigquery_views.tf"
    )


# =========================================================================
# Happy Path: All Gold scheduled query scripts exist
# =========================================================================

GOLD_SQ_FILES = [
    "dim_customer.sql",
    "dim_track.sql",
    "dim_employee.sql",
    "fct_invoice.sql",
    "fct_invoice_line.sql",
]

GOLD_VIEW_TABLE_IDS = [
    "v_dim_customer",
    "v_dim_employee",
    "v_dim_track",
    "v_fct_invoice",
    "v_fct_invoice_line",
]


@pytest.mark.parametrize("filename", GOLD_SQ_FILES)
def test_gold_sq_file_exists(filename):
    filepath = os.path.join(TRANSFORM_DIR, "gold", "sq", filename)
    assert os.path.isfile(filepath), f"Missing Gold scheduled query: gold/sq/{filename}"


@pytest.mark.parametrize("table_id", GOLD_VIEW_TABLE_IDS)
def test_gold_view_in_terraform(table_id):
    """Gold views are managed by Terraform in bigquery_views.tf."""
    assert os.path.isfile(VIEWS_TF), "Missing bigquery_views.tf"
    with open(VIEWS_TF) as f:
        content = f.read()
    assert f'table_id            = "{table_id}"' in content, (
        f"Gold view '{table_id}' not found in bigquery_views.tf"
    )


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
# Happy Path: Silver CQs use INSERT INTO ... APPENDS() pattern
# =========================================================================

@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_uses_insert_into(filename):
    sql = load_sql(filename)
    assert "INSERT INTO" in sql.upper(), (
        f"{filename} must use INSERT INTO pattern"
    )


@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_uses_appends(filename):
    sql = load_sql(filename)
    assert "APPENDS(" in sql.upper() or "APPENDS(" in sql, (
        f"{filename} must use APPENDS() table-valued function"
    )


# =========================================================================
# Happy Path: Gold scheduled queries use INSERT INTO with time window
# =========================================================================

@pytest.mark.parametrize("filename", GOLD_SQ_FILES)
def test_gold_sq_uses_insert_into(filename):
    sql = load_sql(filename)
    assert "INSERT INTO" in sql.upper(), (
        f"{filename} must use INSERT INTO pattern"
    )


@pytest.mark.parametrize("filename", GOLD_SQ_FILES)
def test_gold_sq_uses_time_window(filename):
    sql = load_sql(filename)
    assert "TIMESTAMP_SUB" in sql or "CURRENT_TIMESTAMP" in sql, (
        f"{filename} must use a time-windowed WHERE clause for incremental loading"
    )


@pytest.mark.parametrize("filename", GOLD_SQ_FILES)
def test_gold_sq_no_appends(filename):
    """Gold scheduled queries must NOT use APPENDS() — Iceberg tables don't support CQs."""
    sql = load_sql(filename)
    assert "APPENDS(" not in sql.upper(), (
        f"{filename} must not use APPENDS() — Iceberg tables do not support CQ destinations"
    )


# =========================================================================
# Happy Path: Silver CQs extract from 'after' struct payload
# =========================================================================

@pytest.mark.parametrize("filename", SILVER_CQ_FILES)
def test_silver_cq_uses_after_struct(filename):
    sql = load_sql(filename)
    assert "after." in sql, (
        f"{filename} must extract fields from 'after' RECORD struct (e.g., after.field_name)"
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
        "dim_track must reference silver.album"
    )


def test_dim_track_joins_artist():
    sql = load_sql("gold_dim_track.sql")
    assert "silver.artist" in sql, (
        "dim_track must reference silver.artist"
    )


def test_dim_track_joins_genre():
    sql = load_sql("gold_dim_track.sql")
    assert "silver.genre" in sql, (
        "dim_track must reference silver.genre"
    )


def test_dim_track_joins_media_type():
    sql = load_sql("gold_dim_track.sql")
    assert "silver.media_type" in sql, (
        "dim_track must reference silver.media_type"
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
# Happy Path: Fact queries reference dimension keys
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


# =========================================================================
# Happy Path: Gold views use current-state patterns (checked via TF)
# =========================================================================

def _read_views_tf():
    """Read the bigquery_views.tf file content."""
    with open(VIEWS_TF) as f:
        return f.read()


@pytest.mark.parametrize("view_name", [
    "v_dim_customer",
    "v_dim_employee",
    "v_dim_track",
])
def test_gold_dim_view_filters_active(view_name):
    content = _read_views_tf()
    assert "is_active = TRUE" in content, (
        "Gold dim views must filter for active records"
    )
    assert "ROW_NUMBER()" in content, (
        "Gold dim views must use ROW_NUMBER() for dedup"
    )


@pytest.mark.parametrize("view_name", [
    "v_fct_invoice",
    "v_fct_invoice_line",
])
def test_gold_fact_view_joins_dims(view_name):
    content = _read_views_tf()
    assert "v_dim_customer" in content, (
        "Gold fact views must join with v_dim_customer"
    )

