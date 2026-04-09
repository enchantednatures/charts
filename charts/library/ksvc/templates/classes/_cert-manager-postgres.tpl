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
apiVersion: v1
kind: Secret
metadata:
  name: {{ $serverSecretName }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: database
    cnpg.io/reload: ""
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $pgName }}-server-cert
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: database
spec:
  secretName: {{ $serverSecretName }}
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
    name: {{ $issuerName }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ $clientSecretName }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: database
    cnpg.io/reload: ""
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $pgName }}-client-cert
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: database
spec:
  secretName: {{ $clientSecretName }}
  usages:
    - client auth
  commonName: streaming_replica
  issuerRef:
    name: {{ $issuerName }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
{{- end }}
