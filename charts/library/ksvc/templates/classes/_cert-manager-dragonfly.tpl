{{- define "ksvc.class.certManagerDragonfly" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $df := .Values.dragonfly -}}
{{- $cm := $df.tls.certManager -}}
{{- $globalCM := .Values.global.certManager -}}
{{- $issuerName := $cm.issuerRef.name | default $globalCM.issuerRef.name -}}
{{- $issuerKind := $cm.issuerRef.kind | default $globalCM.issuerRef.kind -}}
{{- $issuerGroup := $cm.issuerRef.group | default $globalCM.issuerRef.group -}}
{{- $secretName := printf "%s-dragonfly-server-tls" $fullname -}}
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
  name: {{ $fullname }}-dragonfly-server-cert
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
    - {{ $fullname }}-dragonfly
    - {{ $fullname }}-dragonfly.{{ .Release.Namespace }}
    - {{ $fullname }}-dragonfly.{{ .Release.Namespace }}.svc
    - {{ $fullname }}-dragonfly.{{ .Release.Namespace }}.svc.cluster.local
  issuerRef:
    name: {{ $issuerName }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
{{- end }}
