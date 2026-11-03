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
ksvc.globalName — Label value for release-wide resources.
When global.nameOverride is set it replaces the release fullname for the
app.kubernetes.io/name label only; resource names stay fullname-based.
*/}}
{{- define "ksvc.globalName" -}}
{{- $override := "" }}
{{- if .Values.global }}
{{-   $override = .Values.global.nameOverride | default "" }}
{{- end }}
{{- if $override }}
{{- $override | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- else }}
{{- include "ksvc.fullname" . }}
{{- end }}
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

{{/*
ksvc.objectBucketNotificationTopicName — Kafka topic and CephBucketTopic name
for one bucket notification. Defaults to <fullname>-<bucket-key>-<event-key>;
objectBuckets.<key>.notifications.<event>.topicName overrides it.
Expects context: dict with "root", "bucketKey", and "eventKey".
*/}}
{{- define "ksvc.objectBucketNotificationTopicName" -}}
{{- $buckets := .root.Values.objectBuckets | default dict -}}
{{- $bucket := index $buckets .bucketKey | default dict -}}
{{- $notifications := $bucket.notifications | default dict -}}
{{- $notification := index $notifications .eventKey | default dict -}}
{{- $override := $notification.topicName | default "" -}}
{{- if $override -}}
{{- $override | trunc 63 | trimSuffix "-" | replace "_" "-" -}}
{{- else -}}
{{- printf "%s-%s-%s" (include "ksvc.fullname" .root) .bucketKey .eventKey | trunc 63 | trimSuffix "-" | replace "_" "-" -}}
{{- end -}}
{{- end }}

{{/*
ksvc.objectBucketNotificationName — CephBucketNotification name (also the
notification label value on the ObjectBucketClaim). It is always derived from
the release/bucket/event so it stays a valid label value even when topicName is
overridden.
*/}}
{{- define "ksvc.objectBucketNotificationName" -}}
{{- printf "%s-%s-%s" (include "ksvc.fullname" .root) .bucketKey .eventKey | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{/*
ksvc.hasObjectBucketNotifications — "true" when at least one enabled bucket
notification exists. Used to decide whether to render Kafka topic resources.
*/}}
{{- define "ksvc.hasObjectBucketNotifications" -}}
{{- $found := false -}}
{{- range $bucketKey, $bucket := .Values.objectBuckets -}}
{{- $notifications := $bucket.notifications | default dict -}}
{{- range $eventKey, $notification := $notifications -}}
{{- if $notification.enabled -}}{{- $found = true -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if $found -}}true{{- end -}}
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

{{- define "ksvc.pingSourceName" -}}
{{- printf "%s-%s-ping-source" (include "ksvc.fullname" .root) .key | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{- define "ksvc.kafkaDlqName" -}}
{{- printf "%s-%s-dlq" (include "ksvc.fullname" .root) .key | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ksvc.kafkaConsumerGroup" -}}
{{- printf "%s-%s-consumers" (include "ksvc.fullname" .root) .key }}
{{- end }}

{{- define "ksvc.kafkaBrokerName" -}}
{{- printf "%s-kafka-broker" (include "ksvc.fullname" .) | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{- define "ksvc.kafkaBrokerConfigName" -}}
{{- printf "%s-kafka-broker-config" (include "ksvc.fullname" .) | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{- define "ksvc.kafkaTriggerName" -}}
{{- printf "%s-%s-trigger" (include "ksvc.fullname" .root) .key | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{- define "ksvc.kafkaTriggerDlqName" -}}
{{- printf "%s-%s-trigger-dlq" (include "ksvc.fullname" .root) .key | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{- define "ksvc.kafkaSourceSaslTypeSecretName" -}}
{{- printf "%s-%s-kafka-sasl-type" (include "ksvc.fullname" .root) .key | trunc 63 | trimSuffix "-" | replace "_" "-" }}
{{- end }}

{{- define "ksvc.kafkaClusterName" -}}
{{- $cluster := .Values.kafka.cluster | default dict -}}
{{- $name := $cluster.name | default "" -}}
{{- if $name -}}
{{- $name | trunc 47 | trimSuffix "-" | replace "_" "-" -}}
{{- else -}}
{{- printf "%s-kafka" (include "ksvc.fullname" .) | trunc 47 | trimSuffix "-" | replace "_" "-" -}}
{{- end -}}
{{- end }}

{{- define "ksvc.kafkaUserName" -}}
{{- $cluster := .Values.kafka.cluster | default dict -}}
{{- $auth := $cluster.auth | default dict -}}
{{- $name := $auth.username | default "" -}}
{{- if $name -}}
{{- $name | trunc 63 | trimSuffix "-" | replace "_" "-" -}}
{{- else -}}
{{- printf "%s-kafka-user" (include "ksvc.fullname" .) | trunc 63 | trimSuffix "-" | replace "_" "-" -}}
{{- end -}}
{{- end }}

{{- define "ksvc.kafkaUserSecretName" -}}
{{- $cluster := .Values.kafka.cluster | default dict -}}
{{- if eq ($cluster.provider | default "strimzi") "redpanda" -}}
{{- printf "%s-kafka-user" (include "ksvc.fullname" .) | trunc 63 | trimSuffix "-" | replace "_" "-" -}}
{{- else -}}
{{- include "ksvc.kafkaUserName" . -}}
{{- end -}}
{{- end }}

{{- define "ksvc.kafkaTopicName" -}}
{{- . | lower | replace "_" "-" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "ksvc.clusterDomain" -}}
{{- $global := .Values.global | default dict -}}
{{- $domain := $global.clusterDomain | default "cluster.local" | toString -}}
{{- $domain | trimSuffix "." -}}
{{- end }}

{{- define "ksvc.kafkaBootstrapServers" -}}
{{- $cluster := .Values.kafka.cluster | default dict -}}
{{- $name := include "ksvc.kafkaClusterName" . -}}
{{- $ns := .Release.Namespace | default "default" -}}
{{- $domain := include "ksvc.clusterDomain" . -}}
{{- $listeners := $cluster.listeners | default dict -}}
{{- $plainPort := int ($listeners.plainPort | default 9092) -}}
{{- $tlsPort := int ($listeners.tlsPort | default 9093) -}}
{{- if eq ($cluster.provider | default "strimzi") "redpanda" -}}
{{- printf "%s.%s.svc.%s:%d" $name $ns $domain $tlsPort -}}
{{- else -}}
{{- if and $cluster.tls $cluster.tls.enabled -}}
{{- printf "%s-kafka-bootstrap.%s.svc.%s:%d" $name $ns $domain $tlsPort -}}
{{- else -}}
{{- printf "%s-kafka-bootstrap.%s.svc.%s:%d" $name $ns $domain $plainPort -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "ksvc.kafkaTopicReplicationFactor" -}}
{{- $cluster := .Values.kafka.cluster | default dict -}}
{{- $replicas := int ($cluster.replicas | default 3) -}}
{{- if eq ($cluster.provider | default "strimzi") "redpanda" -}}
{{- if lt $replicas 3 -}}1{{- else -}}3{{- end -}}
{{- else -}}
{{- if lt $replicas 3 -}}{{- $replicas -}}{{- else -}}3{{- end -}}
{{- end -}}
{{- end }}

{{- define "ksvc.kafkaMinInSyncReplicas" -}}
{{- $rf := int (include "ksvc.kafkaTopicReplicationFactor" .) -}}
{{- if gt $rf 1 -}}{{- sub $rf 1 -}}{{- else -}}1{{- end -}}
{{- end }}
