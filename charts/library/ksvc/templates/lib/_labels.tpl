{{/*
Standard Kubernetes labels applied to all resources.
*/}}
{{- define "ksvc.labels" -}}
app.kubernetes.io/name: {{ include "ksvc.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "ksvc.chart" . }}
{{- if and .Values.global .Values.global.labels }}
{{ toYaml .Values.global.labels }}
{{- end }}
{{- end }}

{{/*
Selector labels (subset for matchLabels).
*/}}
{{- define "ksvc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ksvc.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ksvc.serviceLabels — Labels for a specific service entry.
Expects context: dict with "root" (top-level context), "key" (service map key),
and "svc" (the service config dict).
*/}}
{{- define "ksvc.serviceLabels" -}}
{{- $serviceName := include "ksvc.serviceName" (dict "root" .root "key" .key "svc" .svc) -}}
app.kubernetes.io/name: {{ $serviceName }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ include "ksvc.chart" .root }}
app.kubernetes.io/component: {{ .key }}
{{- if and .root.Values.global .root.Values.global.labels }}
{{ toYaml .root.Values.global.labels }}
{{- end }}
{{- with .svc.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}
