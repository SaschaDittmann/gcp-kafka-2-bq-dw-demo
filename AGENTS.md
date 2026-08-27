# Agent Instructions

## Project Overview

This is a data lakehouse project that ingests data from the PokeAPI, transforms it through a medallion architecture (raw → staging → marts), and deploys to Google BigQuery.

## General Instructions

- **Always read the PRD in `/docs/prds/`** at the start of a new conversation to understand the project's goals and constraints. Files follow the pattern `prd-<topic>.md`
- **Check the tasks in `/docs/tasks/`** before starting a new task. Files follow the pattern `tasks-[prd-file-name].md`
- **Always use Context7 MCP** to look up framework documentation before implementing. Do not rely solely on training data for API usage — libraries evolve and your knowledge may be outdated. Specifically:
  - **dlt:** Look up resource decorators, write dispositions, schema evolution, pipeline configuration
  - **dbt:** Look up dbt-duckdb adapter config, model materialization, schema tests, profiles.yml format
  - **Terraform:** Look up google_composer_environment, google_bigquery_dataset, and other GCP provider resources
  - **DuckDB:** Look up SQL dialect differences from PostgreSQL/BigQuery

## Project Structure

```
ingestion/          # dlt sources and pipelines
transform/          # dbt project (models, tests, macros)
infra/              # Terraform configurations for GCP
app/                # Streamlit dashboard
tests/              # End-to-end and integration tests (pytest)
data/               # Local DuckDB database (gitignored)
docs/prds/          # Product Requirements Documents
docs/tasks/         # Task breakdowns per feature
docs/learnings/     # Documented solutions and patterns
docs/knowledge/     # Framework and library documentation (e.g., llms-full.txt files)
```

## Tech Stack

- **Ingestion:** dlt (data load tool) — Python-based, extracts from PokeAPI, loads to DuckDB/BigQuery
- **Transformation:** dbt with dbt-duckdb (dev) and dbt-bigquery (prod)
- **Local Database:** DuckDB at `data/pokedex.db`
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

## dbt Conventions

- **Schemas:** `raw` (dlt output), `staging` (cleaned), `marts` (analytical)
- **Model naming:** `stg_` prefix for staging, `fct_` for facts, `dim_` for dimensions
- **Testing:** Define tests in `schema.yml` — uniqueness, not-null, accepted values, relationships
- **Run:** `cd transform && dbt build`

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
