# Cloud Run Internal Ingress Debugging

**Date:** 2026-09-02
**Context:** Cloud Run Kafka Connect source service returning 404 despite healthy container

## Problem

The Cloud Run service was configured with `INGRESS_TRAFFIC_INTERNAL_ONLY` but deploy.sh
needed to register connectors via the REST API from outside the VPC. All requests returned
`HTTP 404 Not Found` with an HTML error page from Google Cloud's frontend proxy.

## Key Insight: The 404 is By Design

When Cloud Run is set to **Internal Only** (`--ingress internal`):
- Requests from outside permitted internal networks receive an **HTTP 404** (not 403)
- This is by design — Cloud Run avoids revealing the service's existence
- The 404 never appears in application logs because traffic is dropped **before** reaching the container
- The response has `Content-Type: text/html` and `Alt-Svc` headers (Google infrastructure, not the app)

## Debugging Layers

| Layer | What to Check | Symptom | Our Fix |
|-------|--------------|---------|---------|
| 1. Container Runtime | Port binding (`0.0.0.0:$PORT`), startup | Container failed to start | `CONNECT_LISTENERS=http://0.0.0.0:8083` |
| 2. IAM & Auth | `roles/run.invoker`, identity tokens | 401/403 | `gcloud run services proxy` handles auth |
| 3. Ingress & Routing | Ingress setting vs request source | 404 (network-level) | `INGRESS_TRAFFIC_ALL` |

## How to Distinguish 404 Sources

| Source | Content-Type | Headers | In App Logs? |
|--------|-------------|---------|-------------|
| Cloud Run ingress filter | `text/html; charset=UTF-8` | `Alt-Svc: h3=":443"` | ❌ No |
| Kafka Connect REST API | `application/json` | No `Alt-Svc` | ✅ Yes |

## Issues We Hit (Chronological)

1. **Confluent CUB preflight crash** → Switched to `debezium/connect:2.5` base image
2. **REST port mismatch** → Container used 8083 (default), probe checked 8080
3. **REST binding to 127.0.0.1** → In Kafka 3.x+, `listeners` supersedes deprecated `rest.host.name`/`rest.port`. Set `CONNECT_LISTENERS=http://0.0.0.0:8083`
4. **gcloud proxy not installed** → `sudo apt-get install google-cloud-cli-cloud-run-proxy`
5. **Ingress blocks external traffic** → `INGRESS_TRAFFIC_ALL` (proxy doesn't bypass internal-only ingress)

## Alternative: PSC for Internal-Only Access

For production, keep `INGRESS_TRAFFIC_INTERNAL_ONLY` and use Private Service Connect:
```
[Consumer VPC] → PSC Endpoint → PSC Attachment → ILB + Serverless NEG → Cloud Run
```
This is overengineered for a demo but appropriate for production workloads.

## Resolution

For this demo: `INGRESS_TRAFFIC_ALL` + `gcloud run services proxy` (handles IAM auth).
The service is still protected by IAM — unauthenticated requests get 403.
