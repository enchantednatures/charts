{{/*
Validate required values at template render time.
Call this from the loader to catch misconfigurations early.
*/}}
{{- define "ksvc.validate" -}}
  {{- if not .Values.knativeService.image.repository -}}
    {{- fail "knativeService.image.repository is required" -}}
  {{- end -}}
  {{- if and .Values.postgres.enabled .Values.postgres.backup.enabled (not .Values.postgres.backup.objectStore.destinationPath) -}}
    {{- fail "postgres.backup.objectStore.destinationPath is required when postgres backup is enabled" -}}
  {{- end -}}
  {{- if and .Values.postgres.enabled .Values.postgres.backup.enabled (not .Values.postgres.backup.objectStore.endpointURL) -}}
    {{- fail "postgres.backup.objectStore.endpointURL is required when postgres backup is enabled" -}}
  {{- end -}}
{{- end }}
