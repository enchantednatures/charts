{{- define "ksvc.class.certManagerPostgres" -}}
{{- $pg := .Values.postgres -}}
{{- $cm := $pg.certManager -}}
{{- $globalCM := .Values.global.certManager -}}
{{- $issuerName := $cm.issuerRef.name | default $globalCM.issuerRef.name -}}
{{- $issuerKind := $cm.issuerRef.kind | default $globalCM.issuerRef.kind -}}
{{- $issuerGroup := $cm.issuerRef.group | default $globalCM.issuerRef.group -}}
{{- $pgName := include "ksvc.postgresName" . -}}
{{- $serverSecretName := include "ksvc.postgresServerTLSSecret" . -}}
{{- $serverCASecretName := include "ksvc.postgresServerCASecret" . -}}
{{- $clientCASecretName := include "ksvc.postgresClientCASecret" . -}}
{{- $clientSecretName := include "ksvc.postgresClientTLSSecret" . -}}
{{- /* Chart-managed intermediate Issuers that sign the leaf certificates.
       They are plain cert-manager namespaced Issuers (group cert-manager.io),
       backed by the corresponding CA Secret. The user-configured issuerRef
       signs the CA Certificates, never the leaves — so every CNPG certificate
       secret is backed by the CA that actually signed it. */ -}}
{{- $serverCAIssuerName := printf "%s-server-ca-issuer" $pgName -}}
{{- $clientCAIssuerName := printf "%s-client-ca-issuer" $pgName -}}
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
  annotations:
    helm.sh/resource-policy: keep
    {{- if $globalAnnotations }}
    {{- $globalAnnotations | nindent 4 }}
    {{- end }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ $serverCASecretName | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
    cnpg.io/reload: ""
  annotations:
    helm.sh/resource-policy: keep
    {{- if $globalAnnotations }}
    {{- $globalAnnotations | nindent 4 }}
    {{- end }}
---
{{- /* Server CA: signed by the user-configured issuer, used to sign the server
       leaf certificate below. CNPG receives it as spec.certificates.serverCASecret
       and reads its `ca.crt`. */}}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "{{ $pgName }}-server-ca"
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  secretName: {{ $serverCASecretName | quote }}
  isCA: true
  commonName: "{{ $pgName }}-server-ca"
  privateKey:
    algorithm: ECDSA
    size: 256
  usages:
    - cert sign
    - crl sign
  issuerRef:
    name: {{ $issuerName | quote }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: {{ $serverCAIssuerName | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  ca:
    secretName: {{ $serverCASecretName | quote }}
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
    name: {{ $serverCAIssuerName | quote }}
    kind: Issuer
    group: cert-manager.io
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
  annotations:
    helm.sh/resource-policy: keep
    {{- if $globalAnnotations }}
    {{- $globalAnnotations | nindent 4 }}
    {{- end }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ $clientCASecretName | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
    cnpg.io/reload: ""
  annotations:
    helm.sh/resource-policy: keep
    {{- if $globalAnnotations }}
    {{- $globalAnnotations | nindent 4 }}
    {{- end }}
---
{{- /* Client CA: dedicated client-auth CA signed by the user-configured issuer.
       CNPG receives it as spec.certificates.clientCASecret and verifies general
       mTLS clients against its `ca.crt` — no longer the replication leaf. */}}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "{{ $pgName }}-client-ca"
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  secretName: {{ $clientCASecretName | quote }}
  isCA: true
  commonName: "{{ $pgName }}-client-ca"
  privateKey:
    algorithm: ECDSA
    size: 256
  usages:
    - cert sign
    - crl sign
  issuerRef:
    name: {{ $issuerName | quote }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: {{ $clientCAIssuerName | quote }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  ca:
    secretName: {{ $clientCASecretName | quote }}
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
    name: {{ $clientCAIssuerName | quote }}
    kind: Issuer
    group: cert-manager.io
{{- end }}
