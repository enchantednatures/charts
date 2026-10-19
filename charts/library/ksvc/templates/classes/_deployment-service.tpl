{{/*
ksvc.class.deploymentService — Render a core/v1 Service in front of the Deployment.
Used when services.<key>.workload.type is Deployment; Knative Services are
addressed through the Knative Service itself and never get this document.
Expects context: dict with "root" (top-level context), "key" (service map key),
and "svc" (the merged service config dict).
*/}}
{{- define "ksvc.class.deploymentService" -}}
{{- $serviceName := include "ksvc.serviceName" (dict "root" .root "key" .key "svc" .svc) -}}
{{- $svc := .svc -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ $serviceName }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.serviceLabels" (dict "root" .root "key" .key "svc" $svc) | nindent 4 }}
    {{- with $svc.service.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- $globalAnnotations := include "ksvc.annotations" .root -}}
  {{- if or $globalAnnotations $svc.service.annotations }}
  annotations:
    {{- with $globalAnnotations }}
    {{- . | nindent 4 }}
    {{- end }}
    {{- with $svc.service.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
spec:
  type: {{ $svc.service.type }}
  selector:
    {{- include "ksvc.serviceSelectorLabels" (dict "root" .root "key" .key "svc" $svc) | nindent 4 }}
  ports:
    - name: http
      port: {{ $svc.service.port }}
      targetPort: {{ $svc.port }}
      protocol: TCP
  sessionAffinity: {{ $svc.service.sessionAffinity }}
  {{- if eq $svc.service.sessionAffinity "ClientIP" }}
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: {{ $svc.service.sessionAffinityConfig.clientIP.timeoutSeconds }}
  {{- end }}
  {{- if $svc.service.externalTrafficPolicy }}
  externalTrafficPolicy: {{ $svc.service.externalTrafficPolicy }}
  {{- end }}
{{- end }}
