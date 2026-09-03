---
date: 2026-09-03
topic: BigQuery CQ via REST API
---

# Starting BigQuery Continuous Queries via REST API

## The Problem / Context

The `bq` CLI crashed with a CBA/mTLS Python error when running `bq query --continuous=true`. Additionally, SQL files containing `--` comments were misinterpreted as command-line flags by the `bq` argument parser (`FATAL Flags parsing error: Unknown command line flag ' '`).

## The Solution / Learning

Use the BigQuery REST API `jobs.insert` endpoint with `continuous: true`:

```bash
TOKEN=$(gcloud auth print-access-token)
PROJECT="my-project"

# Strip SQL comments and substitute variables
CQ_SQL=$(sed "s/\${PROJECT_ID}/${PROJECT}/g; /^--/d" transform/silver/cq/customer.sql)

# Submit CQ job via REST API
curl -s -X POST \
  "https://bigquery.googleapis.com/bigquery/v2/projects/${PROJECT}/jobs" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "
import json, sys
sql = sys.stdin.read()
print(json.dumps({
    'configuration': {
        'query': {
            'query': sql,
            'useLegacySql': False,
            'continuous': True
        }
    }
}))" <<< "${CQ_SQL}")"
```

Key points:
- Use `python3` with `json.dumps()` to safely escape SQL in the JSON payload
- Pass SQL via stdin (`<<<`) to avoid shell escaping issues
- Strip `-- comment` lines with `sed '/^--/d'` before passing to avoid flag parsing
- Check `status.state` in response — should be `RUNNING` for CQs
- CQs require BigQuery Enterprise edition with slot reservations

