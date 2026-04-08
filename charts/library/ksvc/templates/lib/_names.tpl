{{/*
Expand the name of the chart.
Knative services MUST use hyphens, never underscores.
*/}}
{{- define "ksvc.name" -}}
{{- $override := "" }}
{{- if .Values.global }}
{{-   $override = .Values.global.nameOverride | default "" }}
{{- end }}
{{- default .Chart.Name $override | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ksvc.fullname" -}}
{{- if and .Values.global .Values.global.fullnameOverride }}
{{- .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}
{{- end }}

{{/*
Chart label value.
*/}}
{{- define "ksvc.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ksvc.serviceName — Derive resource name for a service entry.
Expects context: dict with "root" (top-level context) and "key" (service map key).
Returns: <fullname>-<key>
*/}}
{{- define "ksvc.serviceName" -}}
{{- $fullname := include "ksvc.fullname" .root -}}
{{- printf "%s-%s" $fullname .key | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}
