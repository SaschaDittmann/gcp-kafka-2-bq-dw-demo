# Agent Instructions

## Project Overview

This is a demo of a real-time streaming pipeline running on Google Cloud (GCP).
The data source of this pipeline is a PostgreSQL database hosted by Cloud SQL.
The data will be streamed by using Chance Data Capture (CDC) to a Google Managed Kafka Service, ingested to Google BigQuery, and transformed using BigQuery Continous Queries.

## General Instructions

- **Always read the PRD in `/docs/prds/`** at the start of a new conversation to understand the project's goals and constraints. Files follow the pattern `prd-<topic>.md`
- **Check the tasks in `/docs/tasks/`** before starting a new task. Files follow the pattern `tasks-[prd-file-name].md`
- **Always use Context7 MCP** to look up framework documentation before implementing. Do not rely solely on training data for API usage — libraries evolve and your knowledge may be outdated. Specifically:
  - **Terraform:** Look up google_bigquery_dataset, and other GCP provider resources
  - **BigQuery:** Look up SQL dialect differences from PostgreSQL/BigQuery. 
  - **Kafka** Look up filter and transformation options

## Project Structure

```
transform/          # sql scripts for transformations within BigQuery
infra/              # Terraform configurations for GCP
tests/              # End-to-end and integration tests
data/               # Local database assets
docs/prds/          # Product Requirements Documents
docs/tasks/         # Task breakdowns per feature
docs/learnings/     # Documented solutions and patterns
docs/knowledge/     # Framework and library documentation (e.g., llms-full.txt files)
```

## Tech Stack

- **Data Sources** PostgreSQL hosted on Google Cloud SQL
- **Ingestion:** Google Managed Kafka, Debezium for CDC
- **Transformation:** BigQuery continuous queries
- **Cloud Database:** Google BigQuery
- **Infrastructure:** Terraform for GCP resource provisioning
- **Testing:** pytest for end-to-end tests

## Python Environment

- **Python Version:** 3.11+
- **Package Manager:** `uv`
  - `uv run ...` to run scripts
  - `uv pip install ...` to install packages
  - `uvx ...` to run CLI tools from PyPI
- **Dependencies:** Managed via `requirements.txt`

## Coding Standards

- No `assert` in production code
- Imports at top of file
- Maximum 500 lines per file — split into modules if approaching limit
- Use logging for observability, not print statements
- Use environment variables for configuration (database destination, GCP project, etc.)

## Testing Standards

- Use pytest, not `unittest.TestCase`
- Prefer end-to-end tests with real data over mocked tests
- Test location mirrors source: `ingestion/pipeline.py` → `tests/test_pipeline.py`
- Minimum per component: 1 happy path + 1 edge case + 1 failure case
- Use `@pytest.mark.parametrize` for multiple similar inputs
- Run tests with: `uv run pytest tests/ -v`

## Development Workflow

This project uses a skills-driven AI workflow:

1. **Plan:** `create-prd` → `create-tasks`
2. **Branch:** `git-worktree` (isolated feature branches off `development`)
3. **Build:** `implement-tasks` (code + tests + docs per vertical slice)
4. **Learn:** `document-learnings` (capture solutions in `docs/learnings/`)
5. **Ship:** `finalize-tasks` (clean up, create PR targeting `development`)

## Boundaries

- **Ask first:** Large refactors, new dependencies with broad impact, destructive data changes
- **Never:** Commit secrets or credentials, use destructive git operations unless explicitly requested
