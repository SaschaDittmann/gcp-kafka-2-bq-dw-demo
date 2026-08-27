---
date: 2026-08-27
topic: Idempotent PostgreSQL SQL scripts
---

# Making PostgreSQL Schema and Seed SQL Fully Idempotent

## The Problem / Context
Cloud SQL import (`gcloud sql import sql`) treats any PostgreSQL error as a fatal failure (exit code 3). On re-runs, `ALTER TABLE ADD CONSTRAINT` fails with "constraint already exists" and `INSERT INTO` fails with duplicate primary key violations. This made the init script non-idempotent.

## The Solution / Learning
Three patterns to make PostgreSQL SQL files safe for re-import:

1. **Tables**: `CREATE TABLE IF NOT EXISTS` — built-in PostgreSQL support.
2. **Foreign keys**: Add `ALTER TABLE ... DROP CONSTRAINT IF EXISTS` before each `ALTER TABLE ... ADD CONSTRAINT`. PostgreSQL has no `ADD CONSTRAINT IF NOT EXISTS` syntax.
3. **Seed data**: Append `ON CONFLICT DO NOTHING` to each `INSERT ... VALUES` block. This silently skips rows with existing primary keys.
4. **Indexes**: `CREATE INDEX IF NOT EXISTS` — built-in PostgreSQL support.
5. **Replication/publication**: Wrap in `DO $$ ... IF NOT EXISTS ... END $$` PL/pgSQL blocks checking `pg_replication_slots`, `pg_publication`, and `pg_roles` system catalogs.
