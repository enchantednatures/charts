{{- define "ksvc.class.cnpgPooler" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $pooler := .Values.postgres.pooler -}}
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: {{ $fullname }}-postgres-pooler
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: database
spec:
  cluster:
    name: {{ $fullname }}-postgres
  instances: {{ $pooler.instances }}
  type: {{ $pooler.type }}
  pgbouncer:
    poolMode: {{ $pooler.poolMode }}
    parameters:
      {{- toYaml $pooler.parameters | nindent 6 }}
  template:
    spec:
      resources:
        {{- toYaml $pooler.resources | nindent 8 }}
  monitoring:
    enabled: {{ .Values.postgres.monitoring.enabled }}
    podMonitorEnabled: {{ .Values.postgres.monitoring.enabled }}
{{- end }}
