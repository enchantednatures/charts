{{/*
ksvc.class.pingSource — Render a PingSource for a specific source entry.
Expects context: dict with "root" (top-level context), "key" (source map key),
and "source" (the merged ping source config dict).
The source.sink field must reference a valid key in .Values.services.
*/}}
{{- define "ksvc.class.pingSource" -}}
{{- $source := .source -}}
{{- /* Resolve the sink service name using the sink's own config (honours nameOverride). */ -}}
{{- $sinkSvc := index .root.Values.services $source.sink -}}
{{- $sinkServiceName := include "ksvc.serviceName" (dict "root" .root "key" $source.sink "svc" $sinkSvc) -}}
{{- $sourceName := include "ksvc.pingSourceName" . -}}
{{- $extensions := dict -}}
{{- if and $source.ceOverrides $source.ceOverrides.extensions -}}
  {{- $extensions = $source.ceOverrides.extensions -}}
{{- end -}}
apiVersion: sources.knative.dev/v1
kind: PingSource
metadata:
  name: {{ $sourceName }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: event-source
spec:
  schedule: {{ $source.schedule | quote }}
  timezone: {{ $source.timezone | quote }}
  {{- if $source.contentType }}
  contentType: {{ $source.contentType | quote }}
  {{- end }}
  {{- if $source.data }}
  data: {{ $source.data | quote }}
  {{- end }}
  {{- if $extensions }}
  ceOverrides:
    extensions:
      {{- toYaml $extensions | nindent 6 }}
  {{- end }}
  sink:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: {{ $sinkServiceName }}
{{- end }}
