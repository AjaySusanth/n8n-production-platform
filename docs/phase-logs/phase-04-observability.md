# Phase 4: Observability — Prometheus, Grafana, AlertManager & KEDA Autoscaling

## Architecture Overview

- **kube-prometheus-stack**: Deployed via ArgoCD to manage Prometheus, Grafana, AlertManager, and Kube State Metrics.
- **ServiceMonitors**: Custom Resource Definitions (CRDs) that tell the Prometheus Operator how to dynamically discover scrape endpoints (e.g., n8n metrics port 5678 and Redis exporter port 9121).
- **PrometheusRules**: Kubernetes CRDs defining Prometheus alerting queries (OOMKilled events, workflow failure rate, queue backlog).
- **KEDA (Kubernetes Event-driven Autoscaling)**: Solves the limitation of standard HPA by scaling n8n worker pods based on queue depth in Redis instead of CPU/Memory usage.
- **Redis Ingress Whitelisting**: Calico NetworkPolicies configured to allow inbound traffic to Redis from both the `keda` and `monitoring` namespaces, maintaining a strict default-deny posture.
- **Grafana Dashboard-as-Code**: The custom dashboard JSON is mounted as a Kubernetes ConfigMap labeled for automatic importing by the Grafana sidecar provider.

---

## Implementation Notes

### ServiceMonitors
- *Created `servicemonitors.yaml` within the Helm templates.*
- *Defined two targets: one for the n8n application instances (`main`, `webhook`, `worker`) scraping metrics exported from `/metrics` on port 5678, and one for the Redis exporter on port 9121.*

### Alert Rules (`prometheusrule.yaml`)
- *Created alert group `n8n.rules` containing three core alarms:*
  - `N8nHighWorkflowFailureRate`: Fires if workflow failure rate exceeds 10% over 5 minutes.
  - `N8nWorkerQueueBacklog`: Fires if the queue depth of waiting jobs remains above 20 for 5 minutes.
  - `N8nWorkerOOMKill`: Fires immediately if a container in the `dev` namespace terminates due to an `OOMKilled` reason.

### KEDA ScaledObject (`hpa-worker.yaml`)
- *Configured KEDA to manage the `n8n-dev-worker` Deployment.*
- *Set `minReplicaCount: 1` and `maxReplicaCount: 10` with a `cooldownPeriod` of 300 seconds to prevent scaling thrashing.*
- *Pointed the trigger to the Redis list `bull:jobs:wait` with a threshold of 5 (one worker per 5 jobs).*

### Redis Network Policy (`networkpolicies.yaml`)
- *Added explicit whitelisting rules to the `n8n-dev-allow-db-ingress` NetworkPolicy.*
- *Allowed ingress traffic to the Redis pods from namespaces labeled `kubernetes.io/metadata.name: keda` (ports 6379) and `kubernetes.io/metadata.name: monitoring` (port 9121).*

### DNS FQDN Update
- *Modified KEDA trigger address inside `hpa-worker.yaml` to use the Fully Qualified Domain Name (FQDN): `n8n-dev-redis.dev.svc.cluster.local:6379`.*
- *This enabled the KEDA operator (running in the `keda` namespace) to resolve and query Redis (running in the `dev` namespace).*

### Grafana Dashboard ConfigMap (`dashboard.yaml`)
- *Exported the dashboard JSON from the Grafana UI and wrapped it in a ConfigMap.*
- *Labeled it with `grafana_dashboard: "1"` so that the Grafana dashboard sidecar detects, downloads, and mounts it into the Grafana UI.*

---

## Testing & Verification Process

### 1. Alerting & OOMKill Test
- **Action**: Lowered the worker memory limit artificially:
  ```powershell
  kubectl set resources deployment/n8n-dev-worker -n dev --limits=memory=50Mi
  ```
- **Observation**: Pod failed immediately. Investigated pod events to locate `OOMKilled`.
- **Result**: Port-forwarded to AlertManager and confirmed the `N8nWorkerOOMKill` alert was active and captured.
- **Cleanup**: Restored memory limits back to `1Gi`.

### 2. KEDA Scaling & Load Test
- **Action**: Scaled worker deployment to 0 (to pool jobs without immediate consumption):
  ```powershell
  kubectl scale deployment/n8n-dev-worker --replicas=0 -n dev
  ```
- **Action**: Injected 10 dummy jobs to the Bull queue via Redis CLI:
  ```powershell
  kubectl exec -it n8n-dev-redis-0 -n dev -- redis-cli -a <password> LPUSH bull:jobs:wait job1 job2 job3 job4 job5 job6 job7 job8 job9 job10
  ```
- **Observation**: KEDA detected the queue length of 10.
- **Result**: Watched the worker deployment scale automatically from 0 to 2 replicas. 
- **Cleanup**: The workers booted up, instantly processed the queue (jobs failed due to being raw strings, which is expected by Bull.js), and KEDA successfully scaled the workers back down.

### 3. Dashboard Verification
- **Action**: Port-forwarded to Grafana and checked our custom dashboard.
- **Result**: The dashboard successfully loaded, showing the 5 panels (throughput, success vs failure, queue depth, replica count, and workflow failure %). Verified the 100% failure rate gauge fired during our dummy load test.

---

## Mistakes, Challenges & How You Overcame Them

| Mistake / Challenge | What Went Wrong | How You Fixed It |
|---|---|---|
| **Go Template Conflicts** | Inside `prometheusrule.yaml`, using `{{ $value }}` and `{{ $labels }}` caused Helm linting to fail because Helm tried to parse them as Helm functions. | Escaped the double curly braces by wrapping them in literal strings: `{{ "{{" }} $value {{ "}}" }}`. This instructs Helm to output the raw string for Prometheus to consume. |
| **KEDA DNS Lookup Failures** | KEDA reported `KEDAScalerFailed` because it could not resolve `n8n-dev-redis:6379`. | KEDA runs in a separate namespace (`keda`). Updated the trigger address to use the FQDN `n8n-dev-redis.dev.svc.cluster.local:6379` to allow cross-namespace DNS resolution. |
| **KEDA Network Isolation** | Even after fixing DNS, KEDA could not connect to Redis because of our "default-deny" NetworkPolicy posture in the `dev` namespace. | Updated the Redis NetworkPolicy to whitelist ingress traffic from the `keda` and `monitoring` namespaces. |
| **Dashboard Helm Lint Failures** | Re-importing the Grafana JSON contained `{{gg}}` as a default legend format, which crashed Helm linting. | Replaced `{{gg}}` with `"__auto"` in the JSON template and added the missing `{{- end }}` block at the end of the template. |

---

## Interview Questions From This Phase

### 1. Why scale n8n workers using KEDA instead of standard Kubernetes Horizontal Pod Autoscaler (HPA)?
Standard HPA scales pods based on resource utilization metrics (CPU and Memory). In queue-based applications like n8n, worker pods can be idle (waiting for work, consuming very low CPU) even while the Redis job queue is backing up with hundreds of pending workflows. Alternatively, a single workflow could be highly CPU-intensive, triggering a scale-up even if there are no other jobs in the queue.
KEDA solves this by allowing us to scale directly on the event source—in this case, the Redis list length (`bull:jobs:wait`). We scale baristas based on the length of the order line, not how hard they are sweating.

### 2. Explain how the Grafana Dashboard-as-Code sidecar works. Why not just configure dashboards in the UI?
Configuring dashboards solely in the UI makes them ephemeral; if the Grafana pod restarts or its database is lost, all custom dashboards disappear. 
To implement Dashboard-as-Code, we export the dashboard's JSON model from the UI and commit it to our Helm template inside a `ConfigMap`. We label the ConfigMap with `grafana_dashboard: "1"`. Kube-Prometheus-Stack configures a sidecar container in the Grafana pod that listens to the Kubernetes API. When it detects this ConfigMap and label, it dynamically downloads the JSON and provisions the dashboard into the Grafana instance without requiring a restart.

### 3. What is a Go template escaping issue in Helm, and how did you resolve it?
When writing Prometheus rules (like `PrometheusRule` manifests) in a Helm chart, we use Go template variables like `{{ $value }}` or `{{ $labels.pod }}` to inject dynamic data into alert annotations. However, Helm also uses Go templating. When Helm runs, it tries to compile these variables, fails because they are undefined in the Helm context, and throws an error.
To resolve this, we escape the variables by rendering them as literal strings: `{{ "{{" }} $value {{ "}}" }}`. Helm evaluates this string and renders the literal `{{ $value }}` to the final manifest, allowing Prometheus to read it correctly.

### 4. How did you handle cross-namespace networking for KEDA and Prometheus under a default-deny network policy?
Our default security posture is zero-trust, denying all ingress traffic to our database (Redis/Postgres). Because KEDA runs in the `keda` namespace and Prometheus runs in `monitoring`, they were blocked from communicating with Redis in the `dev` namespace.
To solve this, we:
1. Updated the KEDA connection string to use the fully qualified domain name (FQDN) `n8n-dev-redis.dev.svc.cluster.local:6379` so the DNS lookup succeeds across namespaces.
2. Updated our Redis `NetworkPolicy` to whitelist ingress on port 6379 from the `keda` namespace (for queue length polling) and port 9121 from the `monitoring` namespace (for Prometheus scraper access to the Redis exporter sidecar).
