{{/*
ksvc.class.kafkaSource — Render a KafkaSource for a specific source entry.
Expects context: dict with "root" (top-level context), "key" (source map key),
and "source" (the merged kafka source config dict).

When kafka.broker is defined, the sink points to the Kafka Broker (eventing bus).
Otherwise the source.sink field references a Knative Service directly.
*/}}
{{- define "ksvc.class.kafkaSource" -}}
{{- $source := .source -}}
{{- $sourceName := include "ksvc.kafkaSourceName" . -}}
{{- $dlqName := include "ksvc.kafkaDlqName" . -}}
{{- $hasBroker := and .root.Values.kafka .root.Values.kafka.broker .root.Values.kafka.broker.enabled -}}
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
    {{- if $hasBroker }}
    ref:
      apiVersion: eventing.knative.dev/v1
      kind: Broker
      name: {{ include "ksvc.kafkaBrokerName" .root }}
    {{- else }}
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: {{ include "ksvc.serviceName" (dict "root" .root "key" $source.sink) }}
    {{- end }}
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
