{{/*
ksvc.class.kafkaBrokerConfig — Render the ConfigMap referenced by the Kafka Broker.
Expects context: top-level chart context ($ / .).
The ConfigMap holds Kafka connection details and topic defaults used by the
Knative Kafka Broker data-plane.
*/}}
{{- define "ksvc.class.kafkaBrokerConfig" -}}
{{- $broker := .Values.kafka.broker -}}
{{- $configName := include "ksvc.kafkaBrokerConfigName" . -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $configName }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: kafka-broker-config
data:
  default.topic.partitions: {{ $broker.config.topicPartitions | quote }}
  default.topic.replication.factor: {{ $broker.config.topicReplicationFactor | quote }}
  bootstrap.servers: {{ join "," $broker.config.bootstrapServers | quote }}
  {{- with $broker.config.authSecretName }}
  auth.secret.ref.name: {{ . }}
  {{- end }}
  {{- range $k, $v := $broker.config.extra }}
  {{ $k }}: {{ $v | quote }}
  {{- end }}
{{- end }}

{{/*
ksvc.class.kafkaBroker — Render a Knative Eventing Broker with the Kafka class.
Expects context: top-level chart context ($ / .).
*/}}
{{- define "ksvc.class.kafkaBroker" -}}
{{- $broker := .Values.kafka.broker -}}
{{- $brokerName := include "ksvc.kafkaBrokerName" . -}}
{{- $configName := include "ksvc.kafkaBrokerConfigName" . -}}
apiVersion: eventing.knative.dev/v1
kind: Broker
metadata:
  name: {{ $brokerName }}
  namespace: {{ .Release.Namespace }}
  annotations:
    eventing.knative.dev/broker.class: Kafka
    {{- with $broker.externalTopic }}
    kafka.eventing.knative.dev/external.topic: {{ . }}
    {{- end }}
    {{- $globalAnnotations := include "ksvc.annotations" . -}}
    {{- with $globalAnnotations }}
    {{- . | nindent 4 }}
    {{- end }}
    {{- with $broker.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: kafka-broker
spec:
  config:
    apiVersion: v1
    kind: ConfigMap
    name: {{ $configName }}
    namespace: {{ .Release.Namespace }}
  {{- with $broker.delivery }}
  delivery:
    {{- with .retry }}
    retry: {{ . }}
    {{- end }}
    {{- with .backoffPolicy }}
    backoffPolicy: {{ . }}
    {{- end }}
    {{- with .backoffDelay }}
    backoffDelay: {{ . }}
    {{- end }}
    {{- if and .deadLetterSink .deadLetterSink.enabled }}
    deadLetterSink:
      {{- if .deadLetterSink.uri }}
      uri: {{ .deadLetterSink.uri }}
      {{- else }}
      ref:
        apiVersion: {{ .deadLetterSink.ref.apiVersion | default "serving.knative.dev/v1" }}
        kind: {{ .deadLetterSink.ref.kind | default "Service" }}
        name: {{ required "kafka.broker.delivery.deadLetterSink.ref.name is required when deadLetterSink is enabled" .deadLetterSink.ref.name }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
