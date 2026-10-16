{{/*
ksvc.safeName — Sanitize and length-cap a resource name.

Context: the fully composed, untruncated name (any scalar; rendered via
`toString`). All resource-name helpers funnel through this function so they
behave identically.

For inputs of at most 63 characters the output is byte-identical to the
previous `trunc 63 | trimSuffix "-" | replace "_" "-"` pipeline — existing
release names never change. Longer inputs are shortened deterministically to
`<trunc 52 input>-<sha256(input) truncated to 10>` (always <= 63 characters),
so two names that only differed after character 63 no longer collide on the
same truncated prefix.
*/}}
{{- define "ksvc.safeName" -}}
{{- $full := . | toString -}}
{{- if le (len $full) 63 -}}
{{- $full | trunc 63 | trimSuffix "-" | replace "_" "-" -}}
{{- else -}}
{{- printf "%s-%s" ($full | trunc 52) (sha256sum $full | trunc 10) | replace "_" "-" -}}
{{- end -}}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ksvc.fullname" -}}
{{- if and .Values.global .Values.global.fullnameOverride }}
{{- include "ksvc.safeName" .Values.global.fullnameOverride }}
{{- else }}
{{- include "ksvc.safeName" .Release.Name }}
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
Returns: <fullname>-<suffix>  (or just <fullname> when suffix is empty),
sanitized and capped through ksvc.safeName.
*/}}
{{- define "ksvc.serviceName" -}}
{{- $fullname := include "ksvc.fullname" .root -}}
{{- $suffix := .key -}}
{{- if and .svc (hasKey .svc "nameOverride") -}}
  {{- $suffix = .svc.nameOverride -}}
{{- end -}}
{{- $name := $fullname -}}
{{- if ne ($suffix | toString) "" -}}
  {{- $name = printf "%s-%s" $fullname $suffix -}}
{{- end -}}
{{- include "ksvc.safeName" $name }}
{{- end }}

{{/*
ksvc.objectBucketName — Derive the ObjectBucketClaim (and generated Secret/ConfigMap)
name for an objectBuckets entry. Unlike ksvc.serviceName, nameOverride is not
applicable: the claim is always <fullname>-<key>.
Expects context: dict with "root" (top-level context) and "key" (bucket map key).
Returns: <fullname>-<key>  (sanitized and capped through ksvc.safeName; when the
composed name exceeds 63 chars a deterministic hash suffix keeps it collision-free)
*/}}
{{- define "ksvc.objectBucketName" -}}
{{- include "ksvc.safeName" (printf "%s-%s" (include "ksvc.fullname" .root) .key) }}
{{- end }}

{{- define "ksvc.postgresName" -}}
{{- include "ksvc.safeName" (printf "%s-postgres" (include "ksvc.fullname" .)) }}
{{- end }}

{{- define "ksvc.dragonflyName" -}}
{{- include "ksvc.safeName" (printf "%s-dragonfly" (include "ksvc.fullname" .)) }}
{{- end }}

{{- define "ksvc.postgresBackupStoreName" -}}
{{- include "ksvc.safeName" (printf "%s-postgres-backup-store" (include "ksvc.fullname" .)) }}
{{- end }}

{{- define "ksvc.postgresServerTLSSecret" -}}
{{- include "ksvc.safeName" (printf "%s-postgres-server-tls" (include "ksvc.fullname" .)) }}
{{- end }}

{{/*
ksvc.postgresServerCASecret — Secret holding the server CA that signs the CNPG
server leaf certificate. CloudNativePG reads the `ca.crt` key from it.
*/}}
{{- define "ksvc.postgresServerCASecret" -}}
{{- include "ksvc.safeName" (printf "%s-postgres-server-ca" (include "ksvc.fullname" .)) }}
{{- end }}

{{- define "ksvc.postgresClientTLSSecret" -}}
{{- include "ksvc.safeName" (printf "%s-postgres-client-tls" (include "ksvc.fullname" .)) }}
{{- end }}

{{/*
ksvc.postgresClientCASecret — Secret holding the dedicated client-auth CA that
signs the replication/client leaf certificate. CloudNativePG reads the `ca.crt`
key from it to verify general mTLS client certificates — it must NOT be the
replication leaf secret.
*/}}
{{- define "ksvc.postgresClientCASecret" -}}
{{- include "ksvc.safeName" (printf "%s-postgres-client-ca" (include "ksvc.fullname" .)) }}
{{- end }}

{{- define "ksvc.dragonflyServerTLSSecret" -}}
{{- include "ksvc.safeName" (printf "%s-dragonfly-server-tls" (include "ksvc.fullname" .)) }}
{{- end }}

{{- define "ksvc.kafkaSourceName" -}}
{{- include "ksvc.safeName" (printf "%s-%s-kafka-source" (include "ksvc.fullname" .root) .key) }}
{{- end }}

{{- define "ksvc.kafkaDlqName" -}}
{{- include "ksvc.safeName" (printf "%s-%s-dlq" (include "ksvc.fullname" .root) .key) }}
{{- end }}

{{/*
ksvc.kafkaConsumerGroup — Default consumer group for a KafkaSource.
Also routed through ksvc.safeName so a long fullname cannot produce a
consumer group longer than 63 chars that silently collides after truncation.
*/}}
{{- define "ksvc.kafkaConsumerGroup" -}}
{{- include "ksvc.safeName" (printf "%s-%s-consumers" (include "ksvc.fullname" .root) .key) }}
{{- end }}
