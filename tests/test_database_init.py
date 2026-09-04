"""Tests for Task 2.x: Cloud SQL for PostgreSQL & Database Initialization.

Validates:
- Terraform configuration for Cloud SQL resources
- Chinook schema SQL file structure (11 tables with correct DDL)
- Chinook seed data SQL file structure
- init_db.sh script structure and idempotency design
- Database initialization results (when connected to a live instance)
"""

import json
import os
import re
import subprocess

import pytest

PROJECT_ROOT = os.path.join(os.path.dirname(__file__), "..")
INFRA_DIR = os.path.join(PROJECT_ROOT, "infra")
DATA_DIR = os.path.join(PROJECT_ROOT, "data")


# =========================================================================
# Fixtures
# =========================================================================

@pytest.fixture(scope="module")
def chinook_schema_sql():
    filepath = os.path.join(DATA_DIR, "chinook_schema.sql")
    if not os.path.isfile(filepath):
        pytest.skip("chinook_schema.sql not found")
    with open(filepath) as f:
        return f.read()


@pytest.fixture(scope="module")
def chinook_seed_sql():
    filepath = os.path.join(DATA_DIR, "chinook_seed.sql")
    if not os.path.isfile(filepath):
        pytest.skip("chinook_seed.sql not found")
    with open(filepath) as f:
        return f.read()


@pytest.fixture(scope="module")
def init_db_script():
    filepath = os.path.join(DATA_DIR, "init_db.sh")
    with open(filepath) as f:
        return f.read()


@pytest.fixture(scope="module")
def cloudsql_tf():
    filepath = os.path.join(INFRA_DIR, "cloudsql.tf")
    if not os.path.isfile(filepath):
        pytest.skip("cloudsql.tf not found")
    with open(filepath) as f:
        return f.read()


# =========================================================================
# Happy Path: Required files exist
# =========================================================================

@pytest.mark.parametrize("filename", [
    "data/chinook_schema.sql",
    "data/chinook_seed.sql",
    "data/init_db.sh",
    "infra/cloudsql.tf",
])
def test_required_file_exists(filename):
    filepath = os.path.join(PROJECT_ROOT, filename)
    assert os.path.isfile(filepath), f"Required file missing: {filename}"


def test_init_db_is_executable():
    filepath = os.path.join(DATA_DIR, "init_db.sh")
    assert os.access(filepath, os.X_OK), "init_db.sh must be executable"


# =========================================================================
# Happy Path: Chinook schema contains all 11 tables
# =========================================================================

EXPECTED_TABLES = [
    "customer", "employee", "artist", "album", "track",
    "genre", "media_type", "invoice", "invoice_line",
    "playlist", "playlist_track",
]


@pytest.mark.parametrize("table_name", EXPECTED_TABLES)
def test_schema_contains_create_table(chinook_schema_sql, table_name):
    pattern = rf"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:public\.)?\"?{table_name}\"?"
    assert re.search(pattern, chinook_schema_sql, re.IGNORECASE), (
        f"CREATE TABLE for '{table_name}' not found in chinook_schema.sql"
    )


def test_schema_has_exactly_11_tables(chinook_schema_sql):
    create_count = len(re.findall(
        r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?",
        chinook_schema_sql,
        re.IGNORECASE,
    ))
    assert create_count == 11, (
        f"Expected 11 CREATE TABLE statements, found {create_count}"
    )


# =========================================================================
# Happy Path: Seed data contains INSERT statements for all tables
# =========================================================================

@pytest.mark.parametrize("table_name", EXPECTED_TABLES)
def test_seed_contains_inserts_for_table(chinook_seed_sql, table_name):
    pattern = rf"INSERT\s+INTO\s+(?:public\.)?\"?{table_name}\"?"
    assert re.search(pattern, chinook_seed_sql, re.IGNORECASE), (
        f"INSERT INTO for '{table_name}' not found in chinook_seed.sql"
    )


# =========================================================================
# Happy Path: Terraform Cloud SQL configuration
# =========================================================================

@pytest.mark.parametrize("resource_type", [
    "google_sql_database_instance",
    "google_sql_database",
    "google_sql_user",
])
def test_cloudsql_tf_contains_resource(cloudsql_tf, resource_type):
    assert resource_type in cloudsql_tf, (
        f"Expected resource '{resource_type}' in cloudsql.tf"
    )


def test_cloudsql_tf_enables_logical_decoding(cloudsql_tf):
    assert "cloudsql.logical_decoding" in cloudsql_tf, (
        "cloudsql.tf must set the 'cloudsql.logical_decoding' database flag"
    )


def test_cloudsql_tf_uses_private_ip(cloudsql_tf):
    assert "PRIVATE" in cloudsql_tf or "private_network" in cloudsql_tf, (
        "cloudsql.tf must configure private IP networking"
    )


# =========================================================================
# Happy Path: init_db.sh script structure
# =========================================================================

def test_init_db_creates_replication_user(init_db_script):
    assert "REPLICATION" in init_db_script, (
        "init_db.sh must create a user with REPLICATION role"
    )


def test_init_db_creates_replication_slot(init_db_script):
    assert "pg_create_logical_replication_slot" in init_db_script, (
        "init_db.sh must create a logical replication slot"
    )


def test_init_db_creates_publication(init_db_script):
    assert "CREATE PUBLICATION" in init_db_script, (
        "init_db.sh must create a publication for all tables"
    )


def test_init_db_imports_schema(init_db_script):
    assert "chinook_schema.sql" in init_db_script, (
        "init_db.sh must import chinook_schema.sql"
    )


def test_init_db_imports_seed(init_db_script):
    assert "chinook_seed.sql" in init_db_script, (
        "init_db.sh must import chinook_seed.sql"
    )


def test_init_db_uses_gcloud_sql_import(init_db_script):
    assert "gcloud sql import sql" in init_db_script, (
        "init_db.sh must use 'gcloud sql import sql' for schema/seed loading"
    )


# =========================================================================
# Edge Case: init_db.sh is idempotent (checks before creating)
# =========================================================================

def test_init_db_checks_slot_exists_before_creating(init_db_script):
    assert "pg_replication_slots" in init_db_script, (
        "init_db.sh must check pg_replication_slots before creating a slot"
    )


def test_init_db_checks_publication_exists_before_creating(init_db_script):
    assert "pg_publication" in init_db_script, (
        "init_db.sh must check pg_publication before creating a publication"
    )


def test_init_db_checks_role_exists_before_creating(init_db_script):
    assert "pg_roles" in init_db_script, (
        "init_db.sh must check pg_roles before creating the replication user"
    )


# =========================================================================
# Edge Case: init_db.sh has structured logging
# =========================================================================

def test_init_db_has_timestamped_logging(init_db_script):
    assert "date -u" in init_db_script or "date +" in init_db_script, (
        "init_db.sh must include timestamped log output"
    )


def test_init_db_has_error_handling(init_db_script):
    assert "set -euo pipefail" in init_db_script, (
        "init_db.sh must use 'set -euo pipefail' for strict error handling"
    )


# =========================================================================
# Failure Case: init_db.sh fails without required env vars
# =========================================================================

def test_init_db_requires_instance_name():
    result = subprocess.run(
        ["bash", "-c", "source data/init_db.sh"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        env={**os.environ, "PROJECT_ID": "x", "REPL_PASSWORD": "x"},
        timeout=5,
    )
    assert result.returncode != 0, (
        "init_db.sh should fail when INSTANCE_NAME is not set"
    )
    assert "INSTANCE_NAME" in result.stderr, (
        f"Error message should mention INSTANCE_NAME, got: {result.stderr[:200]}"
    )
