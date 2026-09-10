{{/*
Validate required values at template render time.
Call this from the loader to catch misconfigurations early.
*/}}
{{- define "ksvc.validate" -}}
  {{/* services map must exist and have at least one entry */}}
  {{- if not .Values.services -}}
    {{- fail "services is required and must contain at least one service entry" -}}
  {{- end -}}
  {{- if not (kindIs "map" .Values.services) -}}
    {{- fail "services must be a map (e.g. services: { api: { ... } })" -}}
  {{- end -}}
  {{- if eq (len .Values.services) 0 -}}
    {{- fail "services must contain at least one service entry" -}}
  {{- end -}}

  {{/* each service must have image.repository */}}
  {{- range $key, $svc := .Values.services -}}
    {{- if not $svc.image -}}
      {{- fail (printf "services.%s.image is required" $key) -}}
    {{- end -}}
    {{- if not $svc.image.repository -}}
      {{- fail (printf "services.%s.image.repository is required" $key) -}}
    {{- end -}}
  {{- end -}}

  {{/* postgres backup validation */}}
  {{- if and .Values.postgres.enabled .Values.postgres.backup.enabled (not .Values.postgres.backup.objectStore.destinationPath) -}}
    {{- fail "postgres.backup.objectStore.destinationPath is required when postgres backup is enabled" -}}
  {{- end -}}
  {{- if and .Values.postgres.enabled .Values.postgres.backup.enabled (not .Values.postgres.backup.objectStore.endpointURL) -}}
    {{- fail "postgres.backup.objectStore.endpointURL is required when postgres backup is enabled" -}}
  {{- end -}}

  {{/* kafka source sink validation: each source's sink must reference a valid services key */}}
  {{/* When a kafka broker is enabled, sources sink to the broker so source.sink is optional */}}
  {{- $hasBroker := and .Values.kafka .Values.kafka.broker .Values.kafka.broker.enabled -}}
  {{- if and .Values.kafka .Values.kafka.sources -}}
    {{- range $key, $source := .Values.kafka.sources -}}
      {{- if not $hasBroker -}}
        {{- if not $source.sink -}}
          {{- fail (printf "kafka.sources.%s.sink is required when kafka.broker is not enabled — it must reference a key in the services map" $key) -}}
        {{- end -}}
        {{- if not (hasKey $.Values.services $source.sink) -}}
          {{- fail (printf "kafka.sources.%s.sink references '%s' which does not exist in the services map" $key $source.sink) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* kafka trigger validation */}}
  {{- if and .Values.kafka .Values.kafka.triggers -}}
    {{/* triggers require broker to be enabled */}}
    {{- if not $hasBroker -}}
      {{- fail "kafka.triggers requires kafka.broker.enabled=true — triggers route events from the broker to services" -}}
    {{- end -}}
    {{- range $key, $trigger := .Values.kafka.triggers -}}
      {{- if not $trigger.subscriber -}}
        {{- fail (printf "kafka.triggers.%s.subscriber is required and must reference a key in the services map" $key) -}}
      {{- end -}}
      {{- if not (hasKey $.Values.services $trigger.subscriber) -}}
        {{- fail (printf "kafka.triggers.%s.subscriber references '%s' which does not exist in the services map" $key $trigger.subscriber) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end }}
