{{- define "ksvc.class.cnpgScheduledBackup" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $backup := .Values.postgres.backup -}}
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: {{ $fullname }}-postgres-daily-backup
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: backup
spec:
  schedule: {{ $backup.schedule | quote }}
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
    parameters:
      barmanObjectName: {{ $fullname }}-postgres-backup-store
  cluster:
    name: {{ $fullname }}-postgres
  target: {{ $backup.target }}
{{- end }}
