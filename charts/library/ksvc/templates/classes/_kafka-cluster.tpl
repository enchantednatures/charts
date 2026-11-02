{{- /* ksvc.class.kafkaCluster dispatches to the managed provider. */ -}}
{{- define "ksvc.class.kafkaCluster" -}}
{{- $cluster := .Values.kafka.cluster -}}
{{- if $cluster.enabled -}}
{{- if eq $cluster.provider "redpanda" -}}
{{- include "ksvc.class.kafkaRedpanda" . -}}
{{- else -}}
{{- include "ksvc.class.kafkaStrimzi" . -}}
{{- end -}}
{{- end -}}
{{- end }}
