---
name: helm-chart-authoring
description: Load this skill when writing, debugging, or explaining any Helm chart file including templates, _helpers.tpl, values.yaml, or Chart.yaml
activation: manual
---

# Skill: Helm Chart Authoring for n8n

## Learner Context
The learner has used Helm to *deploy* charts before but has never *written* one from scratch. `_helpers.tpl` was copy-pasted and not understood. This skill rebuilds that understanding from first principles.

## Mental Model to Establish First

Before touching any file, explain this mental model:

```
values.yaml          =  your config variables (like a .env file)
_helpers.tpl         =  reusable functions (define once, call everywhere)
templates/*.yaml     =  Kubernetes manifests with {{ }} placeholders
helm template .      =  renders everything to plain YAML so you can see output
helm lint .          =  checks for syntax errors before applying
```

The `{{ }}` syntax is Go templating. It looks scary but uses only 4 patterns in practice.

## The Four Go Template Patterns Used in This Project

Teach these explicitly before writing any template:

### 1. Print a value from values.yaml
```yaml
image: {{ .Values.n8n.image.repository }}:{{ .Values.n8n.image.tag }}
```
`.Values` = everything in values.yaml. Dot-navigate like a JS object.

### 2. Call a helper function
```yaml
name: {{ include "n8n.fullname" . }}
```
`include` = call a function defined in _helpers.tpl. The `.` passes all context.

### 3. Indent a block (critical for labels)
```yaml
labels:
  {{- include "n8n.labels" . | nindent 4 }}
```
`nindent 4` = add a newline then indent 4 spaces. The `-` strips whitespace before the `{{`. Without this, YAML indentation breaks.

### 4. Conditional block
```yaml
{{- if .Values.ingress.enabled }}
# ingress yaml here
{{- end }}
```

## _helpers.tpl — Teach This Completely

The learner previously copy-pasted this. Rebuild from scratch with explanation.

**What each helper does for this project:**

```go
{{/* The name of the chart */}}
{{- define "n8n.name" -}}
{{- .Chart.Name }}
{{- end }}

{{/* Full release name — used for all resource names */}}
{{- define "n8n.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name }}
{{- end }}

{{/* Worker-specific name */}}
{{- define "n8n.worker.fullname" -}}
{{- printf "%s-worker" (include "n8n.fullname" .) }}
{{- end }}

{{/* Webhook-specific name */}}
{{- define "n8n.webhook.fullname" -}}
{{- printf "%s-webhook" (include "n8n.fullname" .) }}
{{- end }}

{{/* 
  Common labels — applied to EVERY resource.
  Interviewers ask: why do you have these labels?
  Answer: they're Kubernetes recommended labels used by
  kubectl, Helm, and monitoring tools to identify resources.
*/}}
{{- define "n8n.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "n8n.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
  Selector labels — subset of labels used in matchLabels.
  IMPORTANT: these must NEVER change after first deploy.
  Kubernetes uses them to find pods. Changing them orphans old pods.
*/}}
{{- define "n8n.selectorLabels" -}}
app.kubernetes.io/name: {{ include "n8n.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Component-specific selector labels */}}
{{- define "n8n.worker.selectorLabels" -}}
{{ include "n8n.selectorLabels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{- define "n8n.webhook.selectorLabels" -}}
{{ include "n8n.selectorLabels" . }}
app.kubernetes.io/component: webhook
{{- end }}
```

**After showing this, ask:** "Why do we have separate selectorLabels for worker and webhook?" 
Expected answer: so Kubernetes Services can select ONLY worker pods or ONLY webhook pods, not all n8n pods together.

## n8n-Specific Architecture Decisions to Explain

### Why three Deployments, not one with replicas?

The three processes have completely different:
- **Scaling triggers**: main scales on CPU, workers scale on Redis queue depth (KEDA), webhooks scale on request rate
- **Resource profiles**: workers need more CPU/memory (they run workflows), webhooks need low latency
- **Update strategies**: you can roll out new workers without touching the UI

### Why StatefulSet for Postgres and Redis, not Deployment?

Teach this distinction clearly:
- **Deployment**: pods are interchangeable, get random names (pod-abc123), no stable identity
- **StatefulSet**: pods get stable ordinal names (postgres-0, redis-0), restart in order, each gets its own PVC

Redis and Postgres need stable identity because:
- n8n-main has `QUEUE_BULL_REDIS_HOST=redis-0.redis` hardcoded — a random pod name would break reconnection
- Postgres data lives on the PVC attached to postgres-0 specifically

### values.yaml structure to establish upfront

```yaml
n8n:
  image:
    repository: n8nio/n8n
    tag: "1.94.1"        # always pin, never latest
  
  main:
    replicaCount: 1
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

  worker:
    replicaCount: 2      # KEDA will override this dynamically
    resources:
      requests:
        cpu: 500m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1Gi

  webhook:
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 300m
        memory: 256Mi

postgres:
  image:
    repository: postgres
    tag: "16.3"
  storage: 10Gi

redis:
  image:
    repository: redis
    tag: "7.2.5"
  storage: 2Gi

ingress:
  enabled: true
  host: n8n.yourdomain.com
  tlsSecret: n8n-tls

keyvault:
  name: ""
  tenantId: ""
  clientId: ""
```

## Debugging Helm Issues

When `helm install` fails or pods misbehave, teach this sequence:

```bash
# 1. Render templates without applying — see exactly what Kubernetes will receive
helm template n8n ./helm/n8n -f values.yaml

# 2. Check for YAML syntax errors
helm lint ./helm/n8n

# 3. Dry run against live cluster (catches Kubernetes validation errors too)
helm install n8n ./helm/n8n --dry-run --debug

# 4. If installed but broken — check pod events
kubectl describe pod <pod-name> -n n8n

# 5. Check helm release status
helm status n8n -n n8n
helm history n8n -n n8n
```

Common mistakes to call out:
- `nindent` value wrong → YAML indentation error, pod never created
- selectorLabels changed after first install → Helm refuses to upgrade (immutable field)
- Forgot `{{- if }}` around optional blocks → renders empty YAML that fails validation

## Interview Explanation Template

After completing the Helm chart, the learner should be able to say:

"I wrote the Helm chart from scratch rather than using a community chart because I wanted to control the architecture — specifically splitting n8n into three separate Deployments for main, worker, and webhook processes. This lets me scale each one independently based on different metrics. The chart uses _helpers.tpl to define reusable label blocks so every Kubernetes resource has consistent, discoverable metadata without copy-pasting."
