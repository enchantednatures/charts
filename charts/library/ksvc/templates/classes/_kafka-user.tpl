{{- /* ksvc.class.kafkaUsers renders the managed SCRAM user when enabled. */ -}}
{{- define "ksvc.class.kafkaUsers" -}}
{{- $cluster := .Values.kafka.cluster -}}
{{- if and $cluster.enabled (eq $cluster.auth.type "scram") -}}
{{- if eq $cluster.provider "redpanda" -}}
{{- include "ksvc.class.kafkaRedpandaUser" . -}}
{{- else -}}
{{- include "ksvc.class.kafkaStrimziUser" . -}}
{{- end -}}
{{- end -}}
{{- end }}
