{{- /* ksvc.class.kafkaTopics renders one topic CR per distinct source topic. */ -}}
{{- define "ksvc.class.kafkaTopics" -}}
{{- $cluster := .Values.kafka.cluster -}}
{{- if and $cluster.enabled $cluster.topics.create .Values.kafka.sources -}}
{{- $topics := dict -}}
{{- range $key, $source := .Values.kafka.sources -}}
{{- $_ := set $topics $source.topic true -}}
{{- end -}}
{{- $first := true -}}
{{- range $topic, $_ := $topics -}}
{{- if not $first }}
---
{{- end -}}
{{- $first = false -}}
{{- if eq $cluster.provider "redpanda" -}}
{{- include "ksvc.class.kafkaRedpandaTopic" (dict "root" $ "topic" $topic) -}}
{{- else -}}
{{- include "ksvc.class.kafkaStrimziTopic" (dict "root" $ "topic" $topic "name" (include "ksvc.kafkaTopicName" $topic)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
