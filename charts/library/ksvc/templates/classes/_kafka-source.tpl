{{/*
ksvc.class.kafkaSource — Render a KafkaSource for a specific source entry.
Expects context: dict with "root" (top-level context), "key" (source map key),
and "source" (the merged kafka source config dict).
The source.sink field must reference a valid key in .Values.services.
*/}}
{{- define "ksvc.class.kafkaSource" -}}
{{- $source := .source -}}
{{- $sinkServiceName := include "ksvc.serviceName" (dict "root" .root "key" $source.sink) -}}
{{- $sourceName := include "ksvc.kafkaSourceName" . -}}
{{- $dlqName := include "ksvc.kafkaDlqName" . -}}
apiVersion: sources.knative.dev/v1beta1
kind: KafkaSource
metadata:
  name: {{ $sourceName }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: event-source
spec:
  consumerGroup: {{ default (include "ksvc.kafkaConsumerGroup" .) $source.consumerGroup }}
  consumers: {{ $source.consumers }}
  bootstrapServers:
    {{- toYaml $source.bootstrapServers | nindent 4 }}
  topics:
    - {{ $source.topic }}
  sink:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: {{ $sinkServiceName }}
  delivery:
    retry: {{ $source.delivery.retry }}
    backoffPolicy: {{ $source.delivery.backoffPolicy }}
    backoffDelay: {{ $source.delivery.backoffDelay }}
    {{- if and $source.dlq $source.dlq.enabled }}
    deadLetterSink:
      ref:
        apiVersion: serving.knative.dev/v1
        kind: Service
        name: {{ $dlqName }}
    {{- end }}
  initialOffset: {{ $source.initialOffset }}
{{- end }}
