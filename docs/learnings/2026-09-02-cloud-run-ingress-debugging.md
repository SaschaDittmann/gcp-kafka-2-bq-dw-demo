# Cloud Run Internal Ingress Debugging Guide

**Date:** 2026-09-02
**Context:** Cloud Run Kafka Connect source service with internal ingress — systematic debugging

## Overview

Debugging a Cloud Run container configured with **Internal Traffic Only** (`--ingress internal`) and reached via **Private Service Connect (PSC)** or a **Private VPC Connection** involves systematically isolating issues across the **container layer**, **networking/load-balancing layer**, **PSC attachment layer**, and **IAM/DNS layer**.

---

## Key Troubleshooting Flow

| Debugging Layer | What to Check | Common Failure Symptom | Recommended Diagnostic Command / Tool |
|---|---|---|---|
| **1. Container Runtime** | Port binding (`0.0.0.0:$PORT`), startup crashes, health probes | Container failed to start, 500/504 errors | Cloud Logging (`run.googleapis.com/stderr`) |
| **2. IAM & Auth** | `roles/run.invoker`, missing identity tokens | `401 Unauthorized` / `403 Forbidden` | `gcloud run services get-iam-policy` |
| **3. Ingress & Routing** | Ingress setting matching the source path | `404 Not Found` (network-level block) | `gcloud run services describe --format="value(spec.template.metadata.annotations)"` |
| **4. Serverless NEG & ILB** | Serverless NEG attachment, Proxy-only subnet | Connection timeout, 502 Bad Gateway | `gcloud compute backend-services get-health` |
| **5. PSC Endpoint & Attachment** | Connection acceptance list, PSC NAT subnet exhaustion | `PENDING` / `REJECTED`, TCP connection reset | `gcloud compute service-attachments describe` |
| **6. DNS & Host Headers** | Private DNS zone, `Host:` header preservation | SSL mismatch, default page errors | `curl -v -H "Host: <SERVICE_URL>" http(s)://<PSC_IP>` |

---

## Step-by-Step Diagnostic Guide

### Step 1: Verify Container Health & Application Logs

Before troubleshooting the network pipe, confirm the container instance runs and serves requests properly:

1. **Check Container Logs in Cloud Logging**:
   ```sql
   resource.type="cloud_run_revision"
   resource.labels.service_name="YOUR_SERVICE_NAME"
   severity>=WARNING
   ```
2. **Verify Port & Address Binding**: Ensure your application listens on `0.0.0.0:$PORT` (where `$PORT` defaults to `8080`), not `127.0.0.1` or `localhost`.
3. **Check for Startup / Termination Failures**: Look for memory limits (`Memory limit exceeded`) or liveness probe failures in Cloud Logging.

---

### Step 2: Understand the 404 vs 403 Network Behavior

When Cloud Run is set to **Internal Only** (`--ingress internal`):
* Requests sent from outside permitted internal networks receive an immediate **`HTTP 404 Not Found`** from Google Cloud's frontend proxy, rather than a `403 Forbidden` (designed to avoid revealing service existence).
* If your request receives a **404** that never shows up in your Cloud Run application stdout/stderr logs, traffic was dropped by the **Cloud Run Ingress filter** before reaching your container.

**How to distinguish 404 sources:**

| Source | Content-Type | Headers | In App Logs? |
|--------|-------------|---------|-------------|
| Cloud Run ingress filter | `text/html; charset=UTF-8` | `Alt-Svc: h3=":443"` | ❌ No |
| Application (e.g. Kafka Connect) | `application/json` | No `Alt-Svc` | ✅ Yes |

---

### Step 3: Debug the PSC & Internal Load Balancer (ILB) Topology

If Cloud Run is published as a PSC Producer Service via an Internal Application Load Balancer and Serverless NEG:

```
[Consumer VPC / VM]
       │
       ▼ (PSC Forwarding Rule / Endpoint IP)
[PSC Service Attachment]
       │
       ▼ (PSC NAT Subnet)
[Internal App Load Balancer + Serverless NEG]
       │
       ▼
[Cloud Run Container (Ingress: Internal)]
```

1. **Validate PSC Service Attachment State**:
   ```bash
   gcloud compute service-attachments describe SERVICE_ATTACHMENT_NAME \
       --region=REGION
   ```
   * Ensure `connectionStatus` is **`ACCEPTED`** (not `PENDING` or `REJECTED`).
   * Ensure the **PSC NAT Subnet** has available IP capacity.
2. **Check the Serverless NEG Configuration**:
   ```bash
   gcloud compute network-endpoint-groups describe NEG_NAME \
       --region=REGION
   ```
   Confirm the target Cloud Run service name and tag match your current active revision.
3. **Verify Proxy-Only Subnet**: Ensure the VPC containing the Internal Load Balancer has an active `REGIONAL_MANAGED_PROXY` subnet configured with sufficient IP space.

---

### Step 4: Validate DNS and HTTP `Host` Headers

When calling a Cloud Run service via a PSC internal IP address:
* **The HTTP `Host` Header**: The ILB and Cloud Run routing require the incoming request `Host` header to match either your custom domain or the Cloud Run URL.
* **Testing Connectivity from a Consumer VM**:
  ```bash
  # Test direct IP call with Host header override:
  curl -vk -H "Host: YOUR_SERVICE_NAME-XXXXX.a.run.app" \
       -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
       https://<PSC_ENDPOINT_IP>/<ENDPOINT_PATH>
  ```
* **Cloud DNS Setup**: If using domain names, confirm your **Cloud DNS Private Zone** in the consumer VPC correctly maps the domain to the PSC endpoint internal IP.

---

### Step 5: Run Network Intelligence Center Connectivity Tests

Use Google Cloud's **Live Data Plane Analysis** to trace packet drops between the source and the PSC endpoint:
1. Go to **Network Intelligence Center** > **Connectivity Tests**.
2. Set **Source**: The client VM / Subnet in your consumer VPC.
3. Set **Destination**: The PSC Endpoint Forwarding Rule IP and port (e.g., `443` or `80`).
4. Analyze the hop-by-hop evaluation to identify firewall rule rejections, missing routes, or peering mismatches.

---

## Our Project: Issues We Hit (Chronological)

1. **Confluent CUB preflight crash** → Switched to `debezium/connect:2.5` base image (no preflight check)
2. **REST port mismatch** → Container used 8083 (Debezium default), startup probe checked 8080
3. **REST binding to 127.0.0.1** → In Kafka 3.x+, `listeners` supersedes deprecated `rest.host.name`/`rest.port`. Fixed with `CONNECT_LISTENERS=http://0.0.0.0:8083`
4. **gcloud proxy not installed** → `sudo apt-get install google-cloud-cli-cloud-run-proxy`
5. **Ingress blocks external traffic** → `INGRESS_TRAFFIC_ALL` (proxy doesn't bypass internal-only ingress)
6. **IAM auth blocks requests** → Added `allUsers` invoker IAM binding for the demo

## Resolution

For this demo: `INGRESS_TRAFFIC_ALL` + `allUsers` invoker IAM binding.
The service only exposes the Kafka Connect REST API — no sensitive data.

For production: use PSC with Internal Load Balancer (Step 3) or deploy from within the VPC.
