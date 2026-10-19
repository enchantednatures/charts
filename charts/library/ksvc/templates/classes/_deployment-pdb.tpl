{{/*
ksvc.class.deploymentPdb — Render a policy/v1 PodDisruptionBudget for the Deployment.
Rendered only when services.<key>.workload.type is Deployment and
services.<key>.podDisruptionBudget.enabled is true; validators guarantee that
exactly one of minAvailable / maxUnavailable is truthy.
Expects context: dict with "root" (top-level context), "key" (service map key),
and "svc" (the merged service config dict).
*/}}
{{- define "ksvc.class.deploymentPdb" -}}
{{- $serviceName := include "ksvc.serviceName" (dict "root" .root "key" .key "svc" .svc) -}}
{{- $svc := .svc -}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $serviceName }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.serviceLabels" (dict "root" .root "key" .key "svc" $svc) | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "ksvc.serviceSelectorLabels" (dict "root" .root "key" .key "svc" $svc) | nindent 6 }}
  {{- if $svc.podDisruptionBudget.minAvailable }}
  minAvailable: {{ $svc.podDisruptionBudget.minAvailable }}
  {{- else }}
  maxUnavailable: {{ $svc.podDisruptionBudget.maxUnavailable }}
  {{- end }}
{{- end }}
