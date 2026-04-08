{{- define "ksvc.class.cnpgPodMonitor" -}}
{{- $fullname := include "ksvc.fullname" . -}}
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: {{ $fullname }}-postgres-metrics
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app: {{ $fullname }}-postgres
    release: prometheus
spec:
  selector:
    matchLabels:
      postgresql: {{ $fullname }}-postgres
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
      scrapeTimeout: 10s
      path: /metrics
      scheme: http
  namespaceSelector:
    matchNames:
      - {{ .Release.Namespace }}
{{- end }}
