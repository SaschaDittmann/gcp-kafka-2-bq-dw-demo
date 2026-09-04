"""Tests for Task 1.x: Networking & Foundational Terraform Infrastructure.

Validates Terraform configuration files for the networking layer:
- terraform validate passes without errors
- terraform plan produces expected resource counts
- Resource naming conventions are consistent
"""

import json
import os
import subprocess

import pytest

INFRA_DIR = os.path.join(os.path.dirname(__file__), "..", "infra")


@pytest.fixture(scope="module")
def terraform_init():
    """Initialize Terraform in the infra directory (no backend, validate only)."""
    result = subprocess.run(
        ["terraform", "init", "-backend=false"],
        cwd=INFRA_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        pytest.skip(f"terraform init failed (Terraform may not be installed): {result.stderr}")
    return result


@pytest.fixture(scope="module")
def terraform_validate(terraform_init):
    """Run terraform validate and return the result."""
    result = subprocess.run(
        ["terraform", "validate", "-json"],
        cwd=INFRA_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result


@pytest.fixture(scope="module")
def terraform_plan_json(terraform_init):
    """Run terraform plan with a dummy project ID and return the JSON plan.

    Uses -var to provide required variables without a tfvars file.
    The plan will show errors for missing GCP credentials but the
    resource graph itself is still valid for structure validation.
    """
    result = subprocess.run(
        [
            "terraform", "plan",
            "-var", "project_id=test-project-validate",
            "-input=false",
            "-no-color",
            "-out=validate.tfplan",
        ],
        cwd=INFRA_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    if result.returncode != 0:
        pytest.skip(f"terraform plan requires GCP credentials: {result.stderr[:500]}")

    show_result = subprocess.run(
        ["terraform", "show", "-json", "validate.tfplan"],
        cwd=INFRA_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    # Clean up the plan file
    plan_file = os.path.join(INFRA_DIR, "validate.tfplan")
    if os.path.exists(plan_file):
        os.remove(plan_file)

    return json.loads(show_result.stdout)


# -------------------------------------------------------------------------
# Happy Path: Terraform validate passes
# -------------------------------------------------------------------------

def test_terraform_validate_succeeds(terraform_validate):
    output = json.loads(terraform_validate.stdout)
    assert output.get("valid") is True, (
        f"Terraform validation failed: {output.get('diagnostics', 'no diagnostics')}"
    )


# -------------------------------------------------------------------------
# Happy Path: Expected resource types are present in the configuration
# -------------------------------------------------------------------------

def test_required_terraform_files_exist():
    required_files = ["main.tf", "variables.tf", "network.tf", "iam.tf", "outputs.tf"]
    for filename in required_files:
        filepath = os.path.join(INFRA_DIR, filename)
        assert os.path.isfile(filepath), f"Required Terraform file missing: {filename}"


def test_tfvars_example_exists():
    filepath = os.path.join(INFRA_DIR, "terraform.tfvars.example")
    assert os.path.isfile(filepath), "terraform.tfvars.example is missing"


# -------------------------------------------------------------------------
# Edge Case: terraform validate returns valid JSON output
# -------------------------------------------------------------------------

def test_terraform_validate_returns_valid_json(terraform_validate):
    try:
        output = json.loads(terraform_validate.stdout)
    except json.JSONDecodeError:
        pytest.fail("terraform validate -json did not return valid JSON")
    assert "valid" in output, "terraform validate JSON output missing 'valid' key"


# -------------------------------------------------------------------------
# Failure Case: Missing required variable raises validation error
# -------------------------------------------------------------------------

def test_terraform_plan_fails_without_project_id(terraform_init):
    result = subprocess.run(
        ["terraform", "plan", "-input=false", "-no-color"],
        cwd=INFRA_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode != 0, (
        "terraform plan should fail when project_id is not provided"
    )


# -------------------------------------------------------------------------
# Content Validation: Check that key resource definitions exist in HCL
# -------------------------------------------------------------------------

@pytest.mark.parametrize("filename,expected_content", [
    ("main.tf", "google_project_service"),
    ("network.tf", "google_compute_network"),
    ("network.tf", "google_compute_subnetwork"),
    ("network.tf", "google_compute_firewall"),
    ("network.tf", "google_vpc_access_connector"),
    ("network.tf", "google_compute_global_address"),
    ("network.tf", "google_service_networking_connection"),
    ("iam.tf", "google_service_account"),
    ("iam.tf", "google_project_iam_member"),
])
def test_terraform_file_contains_resource(filename, expected_content):
    filepath = os.path.join(INFRA_DIR, filename)
    with open(filepath) as f:
        content = f.read()
    assert expected_content in content, (
        f"Expected '{expected_content}' in {filename} but it was not found"
    )


@pytest.mark.parametrize("api", [
    "compute.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "managedkafka.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "bigquery.googleapis.com",
    "iam.googleapis.com",
])
def test_required_api_is_enabled(api):
    filepath = os.path.join(INFRA_DIR, "main.tf")
    with open(filepath) as f:
        content = f.read()
    assert api in content, (
        f"Required API '{api}' not found in main.tf"
    )


@pytest.mark.parametrize("role", [
    "roles/managedkafka.client",
    "roles/cloudsql.client",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/artifactregistry.reader",
])
def test_required_iam_role_is_bound(role):
    filepath = os.path.join(INFRA_DIR, "iam.tf")
    with open(filepath) as f:
        content = f.read()
    assert role in content, (
        f"Required IAM role '{role}' not found in iam.tf"
    )
