"""Tests for scripts/deploy.sh — validate script structure and content."""
import os
import stat

import pytest

DEPLOY_SCRIPT = os.path.join(
    os.path.dirname(__file__), "..", "scripts", "deploy.sh"
)


@pytest.fixture
def deploy_sh():
    with open(DEPLOY_SCRIPT) as f:
        return f.read()


def test_deploy_script_exists():
    assert os.path.isfile(DEPLOY_SCRIPT), (
        f"Deploy script not found at {DEPLOY_SCRIPT}"
    )


def test_deploy_script_is_executable():
    mode = os.stat(DEPLOY_SCRIPT).st_mode
    assert mode & stat.S_IXUSR, "deploy.sh should be executable by owner"


def test_deploy_script_has_strict_mode(deploy_sh):
    assert "set -euo pipefail" in deploy_sh, (
        "deploy.sh must use strict mode (set -euo pipefail)"
    )


def test_deploy_script_has_shebang(deploy_sh):
    assert deploy_sh.startswith("#!/usr/bin/env bash"), (
        "deploy.sh must start with #!/usr/bin/env bash"
    )


@pytest.mark.parametrize("step_function", [
    "step_init_database",
    "step_build_image",
    "step_update_cloudrun",
    "step_wait_for_cloudrun",
    "step_register_connectors",
    "step_start_continuous_queries",
])
def test_deploy_script_has_step(deploy_sh, step_function):
    assert step_function in deploy_sh, (
        f"deploy.sh missing step function: {step_function}"
    )


def test_deploy_script_loads_terraform_outputs(deploy_sh):
    assert "terraform" in deploy_sh and "output" in deploy_sh, (
        "deploy.sh must load Terraform outputs"
    )


def test_deploy_script_checks_prerequisites(deploy_sh):
    for cmd in ["gcloud", "bq", "terraform"]:
        assert cmd in deploy_sh, (
            f"deploy.sh should check for prerequisite command: {cmd}"
        )


def test_deploy_script_uses_gcloud_builds_submit(deploy_sh):
    assert "gcloud builds submit" in deploy_sh, (
        "deploy.sh should use 'gcloud builds submit' for Docker image build"
    )


def test_deploy_script_calls_init_db(deploy_sh):
    assert "init_db.sh" in deploy_sh, (
        "deploy.sh must call data/init_db.sh for database initialization"
    )


def test_deploy_script_calls_register_connectors(deploy_sh):
    assert "register-connectors.sh" in deploy_sh, (
        "deploy.sh must call connect/register-connectors.sh"
    )


SILVER_CQ_FILES = [
    "customer.sql",
    "employee.sql",
    "track.sql",
    "invoice.sql",
    "invoice_line.sql",
]

# Gold views and scheduled queries are managed by Terraform, not deploy.sh.


@pytest.mark.parametrize("cq_file", SILVER_CQ_FILES)
def test_deploy_script_references_silver_cq_file(deploy_sh, cq_file):
    assert cq_file in deploy_sh, (
        f"deploy.sh should reference Silver CQ file: {cq_file}"
    )


def test_deploy_script_has_skip_flags(deploy_sh):
    for flag in ["SKIP_DB_INIT", "SKIP_IMAGE_BUILD", "SKIP_CQ_START"]:
        assert flag in deploy_sh, (
            f"deploy.sh should support {flag} environment variable"
        )


def test_deploy_script_has_summary_output(deploy_sh):
    assert "Deployment completed" in deploy_sh, (
        "deploy.sh should print a completion summary"
    )

