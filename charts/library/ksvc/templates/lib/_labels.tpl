{{/*
Standard Kubernetes labels applied to all resources.

`app.kubernetes.io/name` identifies the application (the consumer chart name,
honouring `global.nameOverride`) — never the release instance. The release
instance is carried by `app.kubernetes.io/instance` (the fullname). Every value
is quoted so numeric-looking names (e.g. `fullnameOverride: "123"`) can never
render as YAML integers.

Note: `helm.sh/chart` reflects the **consumer** chart (library templates render
in the consumer's context) — intentional library behavior.
*/}}
{{- define "ksvc.labels" -}}
{{- $appName := .Chart.Name -}}
{{- if .Values.global -}}
{{- $appName = default .Chart.Name .Values.global.nameOverride -}}
{{- end -}}
app.kubernetes.io/name: {{ $appName | quote }}
app.kubernetes.io/instance: {{ include "ksvc.fullname" . | quote }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
helm.sh/chart: {{ include "ksvc.chart" . | quote }}
{{- if and .Values.global .Values.global.labels }}
{{ toYaml .Values.global.labels }}
{{- end }}
{{- end }}

{{/*
Selector labels (subset for matchLabels). Mirrors `ksvc.labels`' identity pair:
`name` is the application, `instance` is the release fullname. Quoted.
*/}}
{{- define "ksvc.selectorLabels" -}}
{{- $appName := .Chart.Name -}}
{{- if .Values.global -}}
{{- $appName = default .Chart.Name .Values.global.nameOverride -}}
{{- end -}}
app.kubernetes.io/name: {{ $appName | quote }}
app.kubernetes.io/instance: {{ include "ksvc.fullname" . | quote }}
{{- end }}

{{/*
ksvc.serviceLabels — Labels for a specific service entry.
Expects context: dict with "root" (top-level context), "key" (service map key),
and "svc" (the service config dict).
`name` identifies the service/component (the service map key), while `instance`
is the release fullname. Every value is quoted.
*/}}
{{- define "ksvc.serviceLabels" -}}
app.kubernetes.io/name: {{ .key | quote }}
app.kubernetes.io/instance: {{ include "ksvc.fullname" .root | quote }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service | quote }}
helm.sh/chart: {{ include "ksvc.chart" .root | quote }}
app.kubernetes.io/component: {{ .key | quote }}
{{- if and .root.Values.global .root.Values.global.labels }}
{{ toYaml .root.Values.global.labels }}
{{- end }}
{{- with .svc.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}
