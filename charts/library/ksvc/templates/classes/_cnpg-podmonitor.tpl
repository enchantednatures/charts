{{- define "ksvc.class.cnpgPodMonitor" -}}
{{- $pgName := include "ksvc.postgresName" . -}}
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: "{{ $pgName }}-metrics"
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app: {{ $pgName | quote }}
    {{- $mon := .Values.postgres.monitoring }}
    {{- $pmLabels := $mon.podMonitorLabels }}
    {{- if not (hasKey $mon "podMonitorLabels") }}
      {{- $pmLabels = dict "release" "prometheus" }}
    {{- end }}
    {{- with $pmLabels }}
    {{- toYaml . | trim | nindent 4 }}
    {{- end }}
spec:
  selector:
    matchLabels:
      postgresql: {{ $pgName | quote }}
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
