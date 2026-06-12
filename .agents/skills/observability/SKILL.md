---
name: observability
description: Load this skill when setting up Prometheus, Grafana, AlertManager, writing PromQL, configuring KEDA, or debugging metrics and alerting
activation: manual
---

# Skill: Observability & Autoscaling for n8n Platform

## Learner Context
The learner has used Prometheus and Grafana in P3 but imported dashboards rather than writing PromQL from scratch. This skill pushes them to write real queries and understand what they're measuring. KEDA is completely new — teach from scratch.

## What to Measure for n8n

Before touching any YAML, establish WHAT to measure and WHY:

| Signal | What it tells you | PromQL pattern |
|---|---|---|
| Workflow execution rate | Is n8n processing automations? | `rate(...)` |
| Execution success/failure rate | Are workflows erroring? | `rate()` with label filter |
| Redis queue depth | Are workers keeping up? | gauge query |
| Worker pod count | Is KEDA scaling correctly? | `kube_deployment_spec_replicas` |
| Webhook p99 latency | Are webhooks responding fast? | `histogram_quantile(0.99, ...)` |
| Postgres connection count | Is the DB being overloaded? | gauge |

## PromQL — Teach These Patterns

The learner should write these themselves after seeing the first example.

### Rate (how fast something is happening)
```promql
# n8n workflow executions per second (over last 5 minutes)
rate(n8n_workflow_executions_total[5m])
```
Explain: `rate()` takes a counter (always increasing) and gives you the per-second increase over a time window. Raw counters are useless for dashboards — rate gives you the actual throughput.

### Filtering by label
```promql
# Only failed executions
rate(n8n_workflow_executions_total{status="error"}[5m])
```

### Error rate as percentage
```promql
# What % of executions are failing?
rate(n8n_workflow_executions_total{status="error"}[5m])
/
rate(n8n_workflow_executions_total[5m])
* 100
```

### p99 latency from histogram
```promql
# 99th percentile webhook response time
histogram_quantile(0.99, 
  rate(http_request_duration_seconds_bucket{
    job="n8n-webhook"
  }[5m])
)
```
Explain: histograms record how many requests fell into each latency bucket. `histogram_quantile(0.99, ...)` tells you the latency below which 99% of requests completed. p99 catches outliers that averages hide.

### Redis queue depth (for KEDA)
```promql
# Current depth of the n8n Bull queue in Redis
# This is what KEDA watches to scale workers
redis_connected_clients   # proxy metric if n8n doesn't expose queue depth directly
```

## KEDA — Teach This From Scratch

### What problem does KEDA solve?

Standard HPA scales on CPU and memory. For n8n workers, CPU is not the right signal — a worker might be idle (low CPU) but the queue has 50 pending jobs. You want to scale based on queue depth.

KEDA = Kubernetes Event-Driven Autoscaling. It lets HPA scale on any metric, including Redis queue depth.

Analogy: imagine a coffee shop. Standard HPA would add baristas when they're sweating (high CPU). KEDA adds baristas when the queue of orders is long — which is the actual right signal.

### KEDA Architecture
```
Redis queue → KEDA Metrics Adapter → HPA → Deployment replicas
```

KEDA installs two things:
1. A Metrics Adapter that exposes queue depth as a Kubernetes metric
2. A `ScaledObject` CRD that you define per-deployment

### ScaledObject for n8n Workers

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: n8n-worker-scaler
  namespace: n8n
spec:
  scaleTargetRef:
    name: n8n-worker           # the Deployment to scale
  
  minReplicaCount: 1           # never go to zero — cold start is slow
  maxReplicaCount: 10          # safety cap
  
  # Scale down only after queue has been empty for 5 minutes
  # Prevents thrashing (scale down → queue builds → scale up → repeat)
  cooldownPeriod: 300
  
  triggers:
  - type: redis
    metadata:
      address: redis.n8n.svc.cluster.local:6379
      listName: "bull:jobs:active"   # n8n's Bull queue name in Redis
      listLength: "5"                # one worker per 5 queued jobs
```

After writing this, ask: "What happens if Redis goes down — what does KEDA do?" Answer: falls back to minReplicaCount. Good follow-up for interviews.

## AlertManager Rules — Write Real Alerts

The learner must trigger at least one real alert. Here are the rules to write:

```yaml
groups:
- name: n8n-alerts
  rules:
  
  # Alert when workflow failure rate is high
  - alert: N8nHighWorkflowFailureRate
    expr: |
      rate(n8n_workflow_executions_total{status="error"}[5m])
      /
      rate(n8n_workflow_executions_total[5m])
      > 0.10
    for: 2m    # must be true for 2 minutes before firing (reduces noise)
    labels:
      severity: warning
    annotations:
      summary: "n8n workflow failure rate above 10%"
      description: "{{ $value | humanizePercentage }} of workflows are failing"

  # Alert when worker queue is backing up (KEDA not keeping up)
  - alert: N8nWorkerQueueBacklog
    expr: |
      # If queue depth stays above 20 for 5 minutes, workers can't keep up
      redis_list_length{key="bull:jobs:active"} > 20
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "n8n worker queue backing up"
      description: "{{ $value }} jobs in queue — workers may be undersized"

  # Deliberately trigger this one: lower memory limit below actual usage
  - alert: N8nWorkerOOMKill
    expr: kube_pod_container_status_last_terminated_reason{
      reason="OOMKilled",
      namespace="n8n"
    } == 1
    for: 0m    # fire immediately
    labels:
      severity: critical
    annotations:
      summary: "n8n pod OOMKilled"
```

**Mandatory exercise:** deliberately OOMKill a worker pod:
```bash
# Temporarily lower the memory limit below actual usage
kubectl set resources deployment/n8n-worker -n n8n \
  --limits=memory=50Mi

# Watch the alert fire in AlertManager
# Then fix it and watch it resolve
kubectl set resources deployment/n8n-worker -n n8n \
  --limits=memory=1Gi
```

This is the most memorable debugging story for interviews: "I deliberately OOMKilled my own pod to verify the alert was working."

## Grafana Dashboard Structure

Four panels minimum, written from PromQL scratch (not imported):

1. **Execution throughput** — `rate(n8n_workflow_executions_total[5m])` as time series
2. **Success vs failure** — two lines, `status="success"` and `status="error"`
3. **Worker queue depth** — single stat showing current Redis queue length
4. **Worker replica count** — shows KEDA scaling in action during load test

## Interview Explanation Template

"I set up a full observability stack with Prometheus and Grafana. Rather than importing dashboards, I wrote the PromQL from scratch — tracking workflow execution rate, error rate, and queue depth. For autoscaling, I used KEDA to scale workers based on Redis queue depth rather than CPU, because a worker can be idle but the queue can still be full. I also fired a real AlertManager alert by deliberately OOMKilling a worker pod, which confirmed the alert pipeline was working end-to-end."
