{{- define "ksvc.class.certManagerPostgres" -}}
{{- $pg := .Values.postgres -}}
{{- $cm := $pg.certManager -}}
{{- $globalCM := .Values.global.certManager -}}
{{- $issuerName := $cm.issuerRef.name | default $globalCM.issuerRef.name -}}
{{- $issuerKind := $cm.issuerRef.kind | default $globalCM.issuerRef.kind -}}
{{- $issuerGroup := $cm.issuerRef.group | default $globalCM.issuerRef.group -}}
{{- $pgName := include "ksvc.postgresName" . -}}
{{- $serverSecretName := include "ksvc.postgresServerTLSSecret" . -}}
{{- $clientSecretName := include "ksvc.postgresClientTLSSecret" . -}}
{{- $globalAnnotations := include "ksvc.annotations" . -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ $serverSecretName | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
    cnpg.io/reload: ""
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "{{ $pgName }}-server-cert"
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  secretName: {{ $serverSecretName | quote }}
  usages:
    - server auth
  dnsNames:
    - {{ $pgName }}-rw
    - {{ $pgName }}-rw.{{ .Release.Namespace }}
    - {{ $pgName }}-rw.{{ .Release.Namespace }}.svc
    - {{ $pgName }}-r
    - {{ $pgName }}-r.{{ .Release.Namespace }}
    - {{ $pgName }}-r.{{ .Release.Namespace }}.svc
    - {{ $pgName }}-ro
    - {{ $pgName }}-ro.{{ .Release.Namespace }}
    - {{ $pgName }}-ro.{{ .Release.Namespace }}.svc
  issuerRef:
    name: {{ $issuerName | quote }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ $clientSecretName | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
    cnpg.io/reload: ""
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "{{ $pgName }}-client-cert"
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  secretName: {{ $clientSecretName | quote }}
  usages:
    - client auth
  commonName: streaming_replica
  issuerRef:
    name: {{ $issuerName | quote }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
{{- end }}
