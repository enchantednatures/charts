{{- define "ksvc.class.cnpgPodMonitor" -}}
{{- $pgName := include "ksvc.postgresName" . -}}
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: {{ $pgName }}-metrics
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app: {{ $pgName }}
    release: prometheus
spec:
  selector:
    matchLabels:
      postgresql: {{ $pgName }}
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
