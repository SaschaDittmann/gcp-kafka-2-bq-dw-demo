"""Tests for scripts/teardown.sh — validate script structure and content."""
import os
import stat

import pytest

TEARDOWN_SCRIPT = os.path.join(
    os.path.dirname(__file__), "..", "scripts", "teardown.sh"
)


@pytest.fixture
def teardown_sh():
    with open(TEARDOWN_SCRIPT) as f:
        return f.read()


def test_teardown_script_exists():
    assert os.path.isfile(TEARDOWN_SCRIPT), (
        f"Teardown script not found at {TEARDOWN_SCRIPT}"
    )


def test_teardown_script_is_executable():
    mode = os.stat(TEARDOWN_SCRIPT).st_mode
    assert mode & stat.S_IXUSR, "teardown.sh should be executable by owner"


def test_teardown_script_has_strict_mode(teardown_sh):
    assert "set -euo pipefail" in teardown_sh, (
        "teardown.sh must use strict mode (set -euo pipefail)"
    )


def test_teardown_script_has_shebang(teardown_sh):
    assert teardown_sh.startswith("#!/usr/bin/env bash"), (
        "teardown.sh must start with #!/usr/bin/env bash"
    )


@pytest.mark.parametrize("step_function", [
    "step_cancel_continuous_queries",
    "step_drop_replication_slot",
    "step_drop_publication",
])
def test_teardown_script_has_step(teardown_sh, step_function):
    assert step_function in teardown_sh, (
        f"teardown.sh missing step function: {step_function}"
    )


def test_teardown_cancels_cq_jobs(teardown_sh):
    assert "bq cancel" in teardown_sh or "bq ls --jobs" in teardown_sh, (
        "teardown.sh must cancel running BigQuery Continuous Queries"
    )


def test_teardown_drops_replication_slot(teardown_sh):
    assert "pg_drop_replication_slot" in teardown_sh, (
        "teardown.sh must drop the debezium_slot replication slot"
    )


def test_teardown_drops_publication(teardown_sh):
    assert "DROP PUBLICATION" in teardown_sh, (
        "teardown.sh must drop the debezium_publication"
    )


def test_teardown_uses_gcloud_sql_import(teardown_sh):
    assert "gcloud sql import sql" in teardown_sh, (
        "teardown.sh should use 'gcloud sql import sql' for DB cleanup "
        "(no direct psql access to private Cloud SQL)"
    )


def test_teardown_handles_missing_resources_gracefully(teardown_sh):
    assert "IF EXISTS" in teardown_sh or "does not exist" in teardown_sh, (
        "teardown.sh must handle already-deleted resources gracefully"
    )


def test_teardown_loads_terraform_outputs(teardown_sh):
    assert "terraform" in teardown_sh and "output" in teardown_sh, (
        "teardown.sh must load Terraform outputs for resource identifiers"
    )


def test_teardown_mentions_terraform_destroy(teardown_sh):
    assert "terraform destroy" in teardown_sh, (
        "teardown.sh should remind the user to run 'terraform destroy' after"
    )


def test_teardown_has_summary_output(teardown_sh):
    assert "Teardown completed" in teardown_sh, (
        "teardown.sh should print a completion summary"
    )
