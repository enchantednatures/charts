{{- define "ksvc.class.certManagerPostgres" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $pg := .Values.postgres -}}
{{- $cm := $pg.certManager -}}
{{- $globalCM := .Values.global.certManager -}}
{{- $issuerName := $cm.issuerRef.name | default $globalCM.issuerRef.name -}}
{{- $issuerKind := $cm.issuerRef.kind | default $globalCM.issuerRef.kind -}}
{{- $issuerGroup := $cm.issuerRef.group | default $globalCM.issuerRef.group -}}
{{- $serverSecretName := printf "%s-postgres-server-tls" $fullname -}}
{{- $clientSecretName := printf "%s-postgres-client-tls" $fullname -}}
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
  name: {{ $fullname }}-postgres-server-cert
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: database
spec:
  secretName: {{ $serverSecretName }}
  usages:
    - server auth
  dnsNames:
    - {{ $fullname }}-postgres-rw
    - {{ $fullname }}-postgres-rw.{{ .Release.Namespace }}
    - {{ $fullname }}-postgres-rw.{{ .Release.Namespace }}.svc
    - {{ $fullname }}-postgres-r
    - {{ $fullname }}-postgres-r.{{ .Release.Namespace }}
    - {{ $fullname }}-postgres-r.{{ .Release.Namespace }}.svc
    - {{ $fullname }}-postgres-ro
    - {{ $fullname }}-postgres-ro.{{ .Release.Namespace }}
    - {{ $fullname }}-postgres-ro.{{ .Release.Namespace }}.svc
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
  name: {{ $fullname }}-postgres-client-cert
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
