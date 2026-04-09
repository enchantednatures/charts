{{- define "ksvc.class.cnpgObjectStore" -}}
{{- $store := .Values.postgres.backup.objectStore -}}
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: {{ include "ksvc.postgresBackupStoreName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: backup
spec:
  configuration:
    destinationPath: {{ $store.destinationPath | quote }}
    endpointURL: {{ $store.endpointURL | quote }}
    s3Credentials:
      accessKeyId:
        name: {{ $store.s3Credentials.secretName }}
        key: {{ $store.s3Credentials.accessKeyIdKey }}
      secretAccessKey:
        name: {{ $store.s3Credentials.secretName }}
        key: {{ $store.s3Credentials.secretAccessKeyKey }}
    data:
      compression: {{ $store.data.compression }}
      jobs: {{ $store.data.jobs }}
    wal:
      compression: {{ $store.wal.compression }}
      maxParallel: {{ $store.wal.maxParallel }}
  retentionPolicy: {{ .Values.postgres.backup.retentionPolicy | quote }}
{{- end }}
