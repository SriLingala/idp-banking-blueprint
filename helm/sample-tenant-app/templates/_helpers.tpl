{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "sample-tenant-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "sample-tenant-app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart label.
*/}}
{{- define "sample-tenant-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels — every resource gets these.
*/}}
{{- define "sample-tenant-app.labels" -}}
helm.sh/chart: {{ include "sample-tenant-app.chart" . }}
app.kubernetes.io/name: {{ include "sample-tenant-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
platform.idp/tier: {{ .Values.tier | quote }}
{{- end -}}

{{/*
Selector labels — used by Service, ServiceMonitor, NetworkPolicy.
*/}}
{{- define "sample-tenant-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sample-tenant-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
