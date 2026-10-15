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
Expects context: dict with "root" (top-level context), "key" (service map key),
and "svc" (the service config dict).
When svc.nameOverride is set, it replaces the key as the name suffix.
An empty nameOverride produces just <fullname> (no suffix), which is useful
for single-service deployments that want a clean resource name.
Returns: <fullname>-<suffix>  (or just <fullname> when suffix is empty)
*/}}
{{- define "ksvc.serviceName" -}}
{{- $fullname := include "ksvc.fullname" .root -}}
{{- $suffix := .key -}}
{{- if and .svc (hasKey .svc "nameOverride") -}}
  {{- $suffix = .svc.nameOverride -}}
{{- end -}}
{{- printf "%s-%s" $fullname $suffix | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{/*
ksvc.objectBucketName — Derive the ObjectBucketClaim (and generated Secret/ConfigMap)
name for an objectBuckets entry. Unlike ksvc.serviceName, nameOverride is not
applicable: the claim is always <fullname>-<key>.
Expects context: dict with "root" (top-level context) and "key" (bucket map key).
Returns: <fullname>-<key>  (truncated to 63 chars, trailing dash trimmed)
*/}}
{{- define "ksvc.objectBucketName" -}}
{{- printf "%s-%s" (include "ksvc.fullname" .root) .key | trunc 63 | trimSuffix "-" | replace "_" "-" }}
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

{{/*
ksvc.postgresServerCASecret — Secret holding the server CA that signs the CNPG
server leaf certificate. CloudNativePG reads the `ca.crt` key from it.
*/}}
{{- define "ksvc.postgresServerCASecret" -}}
{{- printf "%s-postgres-server-ca" (include "ksvc.fullname" .) }}
{{- end }}

{{- define "ksvc.postgresClientTLSSecret" -}}
{{- printf "%s-postgres-client-tls" (include "ksvc.fullname" .) }}
{{- end }}

{{/*
ksvc.postgresClientCASecret — Secret holding the dedicated client-auth CA that
signs the replication/client leaf certificate. CloudNativePG reads the `ca.crt`
key from it to verify general mTLS client certificates — it must NOT be the
replication leaf secret.
*/}}
{{- define "ksvc.postgresClientCASecret" -}}
{{- printf "%s-postgres-client-ca" (include "ksvc.fullname" .) }}
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
