{{/*
ksvc.class.kafkaDlq — Render a DLQ Knative Service for a specific kafka source.
Expects context: dict with "root" (top-level context), "key" (source map key),
and "source" (the merged kafka source config dict containing dlq sub-config).
*/}}
{{- define "ksvc.class.kafkaDlq" -}}
{{- $dlq := .source.dlq -}}
{{- $dlqName := include "ksvc.kafkaDlqName" . -}}
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: {{ $dlqName | quote }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: {{ "dlq-handler" | quote }}
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: {{ $dlq.scaling.minScale | quote }}
        autoscaling.knative.dev/max-scale: {{ $dlq.scaling.maxScale | quote }}
    spec:
      {{- /* Effective secrets = the DLQ's own list then the global list; empty
             (both empty) renders nothing. */}}
      {{- with (concat (default (list) $dlq.imagePullSecrets) (default (list) .root.Values.global.imagePullSecrets)) }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
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
          securityContext:
            {{- toYaml $dlq.securityContext | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
{{- end }}
