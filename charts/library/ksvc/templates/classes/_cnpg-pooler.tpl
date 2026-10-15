{{- define "ksvc.class.cnpgPooler" -}}
{{- $pgName := include "ksvc.postgresName" . -}}
{{- $pooler := .Values.postgres.pooler -}}
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: "{{ $pgName }}-pooler"
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- $globalAnnotations := include "ksvc.annotations" . -}}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  cluster:
    name: {{ $pgName | quote }}
  instances: {{ $pooler.instances }}
  type: {{ $pooler.type }}
  pgbouncer:
    poolMode: {{ $pooler.poolMode }}
    parameters:
      {{- toYaml $pooler.parameters | nindent 6 }}
  template:
    spec:
      containers:
        - name: pgbouncer
          resources:
            {{- toYaml $pooler.resources | nindent 12 }}
{{- end }}
