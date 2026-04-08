{{- define "ksvc.class.kafkaDlq" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $dlq := .Values.kafka.dlq -}}
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: {{ $fullname }}-dlq
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
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
