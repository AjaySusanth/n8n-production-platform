{{- define "n8n.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "n8n.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name:= default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63| trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}


{{- define "n8n.main.fullname" -}}
{{- printf "%s-main" (include "n8n.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end}}

{{- define "n8n.worker.fullname" -}}
{{- printf "%s-worker" (include "n8n.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "n8n.webhook.fullname" -}}
{{- printf "%s-webhook" (include "n8n.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "n8n.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "n8n.selectorLabels" .}}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "n8n.selectorLabels" -}}
app.kubernetes.io/name: {{ include "n8n.name" .}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{- define "n8n.main.selectorLabels" -}}
{{ include "n8n.selectorLabels" .}}
app.kubernetes.io/component: main
{{- end }}

{{- define "n8n.worker.selectorLabels" -}}
{{ include "n8n.selectorLabels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{- define "n8n.webhook.selectorLabels" -}}
{{ include "n8n.selectorLabels" . }}
app.kubernetes.io/component: webhook
{{- end }}