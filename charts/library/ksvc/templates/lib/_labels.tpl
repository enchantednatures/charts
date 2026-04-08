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
