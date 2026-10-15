{{- define "ksvc.class.cnpgObjectStore" -}}
{{- $store := .Values.postgres.backup.objectStore -}}
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: {{ include "ksvc.postgresBackupStoreName" . | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "backup" | quote }}
  {{- $globalAnnotations := include "ksvc.annotations" . -}}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  configuration:
    destinationPath: {{ $store.destinationPath | quote }}
    endpointURL: {{ $store.endpointURL | quote }}
    s3Credentials:
      accessKeyId:
        name: {{ $store.s3Credentials.secretName | quote }}
        key: {{ $store.s3Credentials.accessKeyIdKey }}
      secretAccessKey:
        name: {{ $store.s3Credentials.secretName | quote }}
        key: {{ $store.s3Credentials.secretAccessKeyKey }}
    data:
      compression: {{ $store.data.compression }}
      jobs: {{ $store.data.jobs }}
    wal:
      compression: {{ $store.wal.compression }}
      maxParallel: {{ $store.wal.maxParallel }}
  retentionPolicy: {{ .Values.postgres.backup.retentionPolicy | quote }}
{{- end }}
