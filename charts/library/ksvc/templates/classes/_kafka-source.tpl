{{/*
ksvc.class.kafkaSource — Render a KafkaSource for a specific source entry.
Expects context: dict with "root" (top-level context), "key" (source map key),
and "source" (the merged kafka source config dict).
The source.sink field must reference a valid key in .Values.services.
*/}}
{{- define "ksvc.class.kafkaSource" -}}
{{- $source := .source -}}
{{- /* Resolve the sink service name using the sink's own config (honours nameOverride). */ -}}
{{- $sinkSvc := index .root.Values.services $source.sink -}}
{{- $sinkServiceName := include "ksvc.serviceName" (dict "root" .root "key" $source.sink "svc" $sinkSvc) -}}
{{- $sourceName := include "ksvc.kafkaSourceName" . -}}
{{- $dlqName := include "ksvc.kafkaDlqName" . -}}
apiVersion: sources.knative.dev/v1beta1
kind: KafkaSource
metadata:
  name: {{ $sourceName | quote }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: {{ "event-source" | quote }}
  {{- $globalAnnotations := include "ksvc.annotations" .root -}}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  consumerGroup: {{ default (include "ksvc.kafkaConsumerGroup" .) $source.consumerGroup | quote }}
  consumers: {{ $source.consumers }}
  bootstrapServers:
    {{- toYaml $source.bootstrapServers | nindent 4 }}
  topics:
    - {{ $source.topic }}
  sink:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: {{ $sinkServiceName | quote }}
  delivery:
    retry: {{ $source.delivery.retry }}
    backoffPolicy: {{ $source.delivery.backoffPolicy }}
    backoffDelay: {{ $source.delivery.backoffDelay }}
    {{- if and $source.dlq $source.dlq.enabled }}
    deadLetterSink:
      ref:
        apiVersion: serving.knative.dev/v1
        kind: Service
        name: {{ $dlqName | quote }}
    {{- end }}
  initialOffset: {{ $source.initialOffset }}
{{- end }}
