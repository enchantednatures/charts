{{- define "ksvc.class.cnpgScheduledBackup" -}}
{{- $backup := .Values.postgres.backup -}}
{{- $pgName := include "ksvc.postgresName" . -}}
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: {{ $pgName }}-daily-backup
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
      barmanObjectName: {{ include "ksvc.postgresBackupStoreName" . }}
  cluster:
    name: {{ $pgName }}
  target: {{ $backup.target }}
{{- end }}
