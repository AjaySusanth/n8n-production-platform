# n8n Production Platform — NetworkPolicy Communication Matrix

This document defines the network communication matrix for the n8n production platform on AKS, derived from the NetworkPolicies defined in `helm/n8n/templates/networkpolicies.yaml`.

## Communication Matrix

| Source Component | Destination Component | Protocol / Port | Allowed / Denied | NetworkPolicy Rule / Reason |
| :--- | :--- | :--- | :--- | :--- |
| **Ingress Controller** | `n8n-main` | TCP / 5678 | **ALLOWED** | `allow-http-ingress` (Path routing for web UI/API) |
| **Ingress Controller** | `n8n-webhook` | TCP / 5678 | **ALLOWED** | `allow-http-ingress` (Path routing for webhook endpoints) |
| **Ingress Controller** | `n8n-worker` | Any | **DENIED** | `default-deny` (Worker has no ingress port exposed) |
| **Ingress Controller** | `n8n-postgres` / `n8n-redis` | Any | **DENIED** | `default-deny` (Blocked from accessing storage layers directly) |
| **n8n-main** | `n8n-postgres` | TCP / 5432 | **ALLOWED** | `allow-n8n-egress` & `allow-db-ingress` (Stores workflow configs & logs) |
| **n8n-main** | `n8n-redis` | TCP / 6379 | **ALLOWED** | `allow-n8n-egress` & `allow-db-ingress` (Pushes jobs to execution queue) |
| **n8n-main** | `n8n-webhook` / `n8n-worker` | Any | **DENIED** | `default-deny` (Components communicate asynchronously via Redis) |
| **n8n-webhook** | `n8n-redis` | TCP / 6379 | **ALLOWED** | `allow-n8n-egress` & `allow-db-ingress` (Pushes webhook jobs to queue) |
| **n8n-webhook** | `n8n-postgres` | TCP / 5432 | **ALLOWED** | `allow-n8n-egress` & `allow-db-ingress` (Fetches webhook/workflow details) |
| **n8n-webhook** | `n8n-main` / `n8n-worker` | Any | **DENIED** | `default-deny` (Separated by design) |
| **n8n-worker** | `n8n-postgres` | TCP / 5432 | **ALLOWED** | `allow-n8n-egress` & `allow-db-ingress` (Writes execution results) |
| **n8n-worker** | `n8n-redis` | TCP / 6379 | **ALLOWED** | `allow-n8n-egress` & `allow-db-ingress` (Pulls jobs from execution queue) |
| **n8n-worker** | `n8n-main` / `n8n-webhook` | Any | **DENIED** | `default-deny` (Separated by design) |
| **KEDA Operator** | `n8n-redis` | TCP / 6379 | **ALLOWED** | `allow-db-ingress` (Namespace `keda` allowed to poll Redis queue length) |
| **Prometheus** | `n8n-main` | TCP / 5678 | **ALLOWED** | `allow-prometheus-ingress` (Namespace `monitoring` scrapes app metrics) |
| **Prometheus** | `n8n-redis` | TCP / 9121 | **ALLOWED** | `allow-db-ingress` (Scrapes metrics from `redis-exporter` sidecar) |
| **Any Pod** | `CoreDNS` | UDP/TCP / 53 | **ALLOWED** | `allow-dns` (Necessary for name resolution) |
| **Any Pod** | `Azure IMDS` | TCP / 80 | **ALLOWED** | `allow-imds` (Egress to `169.254.169.254` for Key Vault CSI authentication) |
| `n8n-main`, `webhook`, `worker` | **Public Internet** | TCP / 443 | **ALLOWED** | `allow-n8n-egress` (To make HTTP/HTTPS calls to external API nodes) |
