{{/*
ksvc.class.kafkaTrigger — Render a Knative Eventing Trigger for a specific trigger entry.
Expects context: dict with "root" (top-level context), "key" (trigger map key),
and "trigger" (the merged kafka trigger config dict).

The trigger routes events from the Kafka Broker to a Knative Service.
Supports both legacy filter (attributes) and modern filters (exact, prefix,
suffix, all, any, not, cesql).
*/}}
{{- define "ksvc.class.kafkaTrigger" -}}
{{- $trigger := .trigger -}}
{{- $triggerName := include "ksvc.kafkaTriggerName" . -}}
{{- $brokerName := include "ksvc.kafkaBrokerName" .root -}}
{{- $subscriberName := include "ksvc.serviceName" (dict "root" .root "key" $trigger.subscriber) -}}
apiVersion: eventing.knative.dev/v1
kind: Trigger
metadata:
  name: {{ $triggerName }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: kafka-trigger
  {{- if or $trigger.annotations (include "ksvc.annotations" .root) }}
  annotations:
    {{- $globalAnnotations := include "ksvc.annotations" .root -}}
    {{- with $globalAnnotations }}
    {{- . | nindent 4 }}
    {{- end }}
    {{- with $trigger.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
spec:
  broker: {{ $brokerName }}
  {{- if $trigger.filter }}
  filter:
    attributes:
      {{- toYaml $trigger.filter | nindent 6 }}
  {{- end }}
  {{- with $trigger.filters }}
  filters:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  subscriber:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: {{ $subscriberName }}
    {{- with $trigger.subscriberUri }}
    uri: {{ . }}
    {{- end }}
  {{- if or $trigger.delivery $trigger.dlq }}
  delivery:
    {{- with $trigger.delivery }}
    {{- with .retry }}
    retry: {{ . }}
    {{- end }}
    {{- with .backoffPolicy }}
    backoffPolicy: {{ . }}
    {{- end }}
    {{- with .backoffDelay }}
    backoffDelay: {{ . }}
    {{- end }}
    {{- end }}
    {{- if and $trigger.dlq $trigger.dlq.enabled }}
    deadLetterSink:
      ref:
        apiVersion: serving.knative.dev/v1
        kind: Service
        name: {{ include "ksvc.kafkaTriggerDlqName" . }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
ksvc.class.kafkaTriggerDlq — Render a DLQ Knative Service for a specific trigger.
Expects context: dict with "root" (top-level context), "key" (trigger map key),
and "trigger" (the merged kafka trigger config dict containing dlq sub-config).
*/}}
{{- define "ksvc.class.kafkaTriggerDlq" -}}
{{- $dlq := .trigger.dlq -}}
{{- $dlqName := include "ksvc.kafkaTriggerDlqName" . -}}
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: {{ $dlqName }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: trigger-dlq-handler
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: {{ $dlq.scaling.minScale | quote }}
        autoscaling.knative.dev/max-scale: {{ $dlq.scaling.maxScale | quote }}
    spec:
      containers:
        - name: dlq-handler
          image: {{ $dlq.image.repository }}:{{ $dlq.image.tag }}
          ports:
            - containerPort: 8080
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          resources:
            {{- toYaml $dlq.resources | nindent 12 }}
{{- end }}
