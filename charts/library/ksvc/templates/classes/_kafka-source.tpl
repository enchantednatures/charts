{{- define "ksvc.class.kafkaSource" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $kafka := .Values.kafka -}}
apiVersion: sources.knative.dev/v1beta1
kind: KafkaSource
metadata:
  name: {{ $fullname }}-kafka-source
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: event-source
spec:
  consumerGroup: {{ default (printf "%s-consumers" $fullname) $kafka.source.consumerGroup }}
  consumers: {{ $kafka.source.consumers }}
  bootstrapServers:
    {{- toYaml $kafka.source.bootstrapServers | nindent 4 }}
  topics:
    - {{ $kafka.source.topic }}
  sink:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: {{ $fullname }}
  delivery:
    retry: {{ $kafka.delivery.retry }}
    backoffPolicy: {{ $kafka.delivery.backoffPolicy }}
    backoffDelay: {{ $kafka.delivery.backoffDelay }}
    {{- if $kafka.dlq.enabled }}
    deadLetterSink:
      ref:
        apiVersion: serving.knative.dev/v1
        kind: Service
        name: {{ $fullname }}-dlq
    {{- end }}
  initialOffset: {{ $kafka.source.initialOffset }}
{{- end }}
