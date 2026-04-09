{{- define "ksvc.class.certManagerDragonfly" -}}
{{- $df := .Values.dragonfly -}}
{{- $cm := $df.tls.certManager -}}
{{- $globalCM := .Values.global.certManager -}}
{{- $issuerName := $cm.issuerRef.name | default $globalCM.issuerRef.name -}}
{{- $issuerKind := $cm.issuerRef.kind | default $globalCM.issuerRef.kind -}}
{{- $issuerGroup := $cm.issuerRef.group | default $globalCM.issuerRef.group -}}
{{- $dfName := include "ksvc.dragonflyName" . -}}
{{- $secretName := include "ksvc.dragonflyServerTLSSecret" . -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ $secretName }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: cache
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $dfName }}-server-cert
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: cache
spec:
  secretName: {{ $secretName }}
  {{- if $cm.duration }}
  duration: {{ $cm.duration }}
  {{- end }}
  {{- if $cm.renewBefore }}
  renewBefore: {{ $cm.renewBefore }}
  {{- end }}
  usages:
    - server auth
  dnsNames:
    - {{ $dfName }}
    - {{ $dfName }}.{{ .Release.Namespace }}
    - {{ $dfName }}.{{ .Release.Namespace }}.svc
    - {{ $dfName }}.{{ .Release.Namespace }}.svc.cluster.local
  issuerRef:
    name: {{ $issuerName }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
{{- end }}
