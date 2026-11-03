{{- define "ksvc.class.cnpgPodMonitor" -}}
{{- $pgName := include "ksvc.postgresName" . -}}
{{- $mon := .Values.postgres.monitoring -}}
{{- $labels := dict "app" $pgName -}}
{{- $labels = mustMergeOverwrite $labels (deepCopy ($mon.podMonitor.labels | default dict)) -}}
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: {{ $pgName }}-metrics
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    {{- toYaml $labels | nindent 4 }}
spec:
  selector:
    matchLabels:
      postgresql: {{ $pgName }}
  podMetricsEndpoints:
    - port: metrics
      interval: {{ $mon.podMonitor.interval }}
      scrapeTimeout: {{ $mon.podMonitor.scrapeTimeout }}
      path: {{ $mon.podMonitor.path }}
      scheme: {{ $mon.podMonitor.scheme }}
  namespaceSelector:
    matchNames:
      - {{ .Release.Namespace }}
{{- end }}
