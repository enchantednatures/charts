{{/*
Common annotations applied to all resources.
*/}}
{{- define "ksvc.annotations" -}}
{{- if and .Values.global .Values.global.annotations }}
{{- toYaml .Values.global.annotations }}
{{- end }}
{{- end }}
