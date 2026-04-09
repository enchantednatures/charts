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

{{- define "ksvc.postgresName" -}}
{{- printf "%s-postgres" (include "ksvc.fullname" .) }}
{{- end }}

{{- define "ksvc.dragonflyName" -}}
{{- printf "%s-dragonfly" (include "ksvc.fullname" .) }}
{{- end }}

{{- define "ksvc.postgresBackupStoreName" -}}
{{- printf "%s-postgres-backup-store" (include "ksvc.fullname" .) }}
{{- end }}

{{- define "ksvc.postgresServerTLSSecret" -}}
{{- printf "%s-postgres-server-tls" (include "ksvc.fullname" .) }}
{{- end }}

{{- define "ksvc.postgresClientTLSSecret" -}}
{{- printf "%s-postgres-client-tls" (include "ksvc.fullname" .) }}
{{- end }}

{{- define "ksvc.dragonflyServerTLSSecret" -}}
{{- printf "%s-dragonfly-server-tls" (include "ksvc.fullname" .) }}
{{- end }}

{{- define "ksvc.kafkaSourceName" -}}
{{- printf "%s-%s-kafka-source" (include "ksvc.fullname" .root) .key | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ksvc.kafkaDlqName" -}}
{{- printf "%s-%s-dlq" (include "ksvc.fullname" .root) .key | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ksvc.kafkaConsumerGroup" -}}
{{- printf "%s-%s-consumers" (include "ksvc.fullname" .root) .key }}
{{- end }}
