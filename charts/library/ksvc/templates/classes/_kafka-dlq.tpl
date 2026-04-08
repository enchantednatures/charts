{{/*
ksvc.class.kafkaDlq — Render a DLQ Knative Service for a specific kafka source.
Expects context: dict with "root" (top-level context), "key" (source map key),
and "source" (the merged kafka source config dict containing dlq sub-config).
*/}}
{{- define "ksvc.class.kafkaDlq" -}}
{{- $fullname := include "ksvc.fullname" .root -}}
{{- $dlq := .source.dlq -}}
{{- $dlqName := printf "%s-%s-dlq" $fullname .key | trunc 63 | trimSuffix "-" -}}
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: {{ $dlqName }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: dlq-handler
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
