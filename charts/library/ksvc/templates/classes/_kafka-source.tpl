{{/*
ksvc.class.kafkaSource — Render a KafkaSource for a specific source entry.
Expects context: dict with "root" (top-level context), "key" (source map key),
and "source" (the merged kafka source config dict).
The source.sink field must reference a valid key in .Values.services.
*/}}
{{- define "ksvc.class.kafkaSource" -}}
{{- $source := .source -}}
{{- $hasBroker := and .root.Values.kafka .root.Values.kafka.broker .root.Values.kafka.broker.enabled -}}
{{- $sinkServiceName := "" -}}
{{- if not $hasBroker -}}
{{- /* Resolve the sink service name using the sink's own config (honours nameOverride). */ -}}
{{- $sinkSvc := index .root.Values.services $source.sink -}}
{{- $sinkServiceName = include "ksvc.serviceName" (dict "root" .root "key" $source.sink "svc" $sinkSvc) -}}
{{- end -}}
{{- $sourceName := include "ksvc.kafkaSourceName" . -}}
{{- $dlqName := include "ksvc.kafkaDlqName" . -}}
{{- $net := $source.net | default dict -}}
{{- $tls := $net.tls | default dict -}}
{{- $sasl := $net.sasl | default dict -}}
{{- $managed := and .root.Values.kafka .root.Values.kafka.cluster .root.Values.kafka.cluster.enabled -}}
{{- $saslSecretName := include "ksvc.kafkaSourceSaslTypeSecretName" (dict "root" .root "key" .key) -}}
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
      name: {{ $sinkServiceName }}
    {{- end }}
  {{- if or $tls.enabled $sasl.enabled }}
  net:
    {{- if $tls.enabled }}
    tls:
      enable: true
      {{- if $tls.caCertSecret }}
      caCert:
        secretKeyRef:
          name: {{ $tls.caCertSecret }}
          key: {{ $tls.caCertKey | default "ca.crt" }}
      {{- end }}
      {{- if $tls.certSecret }}
      cert:
        secretKeyRef:
          name: {{ $tls.certSecret }}
          key: {{ $tls.certKey | default "tls.crt" }}
      {{- end }}
      {{- if $tls.keySecret }}
      key:
        secretKeyRef:
          name: {{ $tls.keySecret }}
          key: {{ $tls.keyKey | default "tls.key" }}
      {{- end }}
    {{- end }}
    {{- if $sasl.enabled }}
    sasl:
      enable: true
      type:
        secretKeyRef:
          name: {{ $saslSecretName }}
          key: saslType
      {{- $userSecret := $sasl.userSecret -}}
      {{- if and $managed (not $userSecret) -}}
        {{- $userSecret = $saslSecretName -}}
      {{- end -}}
      {{- if $userSecret }}
      user:
        secretKeyRef:
          name: {{ $userSecret }}
          key: {{ $sasl.userKey | default "user" }}
      {{- end }}
      {{- if $sasl.passwordSecret }}
      password:
        secretKeyRef:
          name: {{ $sasl.passwordSecret }}
          key: {{ $sasl.passwordKey | default "password" }}
      {{- end }}
    {{- end }}
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

{{/*
ksvc.class.kafkaSaslTypeSecret — Render the per-source Secret that supplies the
KafkaSource SASL mechanism and, in managed mode, the managed username.
Expects context: dict with "root", "key", and "source".
*/}}
{{- define "ksvc.class.kafkaSaslTypeSecret" -}}
{{- $sasl := .source.net.sasl -}}
{{- $name := include "ksvc.kafkaSourceSaslTypeSecretName" (dict "root" .root "key" .key) -}}
{{- $managed := and .root.Values.kafka .root.Values.kafka.cluster .root.Values.kafka.cluster.enabled -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ $name }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: kafka-source-auth
type: Opaque
stringData:
  saslType: {{ $sasl.mechanism | quote }}
  {{- if and $managed (eq .root.Values.kafka.cluster.auth.type "scram") }}
  user: {{ include "ksvc.kafkaUserName" .root | quote }}
  {{- end }}
{{- end }}
