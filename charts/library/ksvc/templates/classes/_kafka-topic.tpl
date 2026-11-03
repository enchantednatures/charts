{{- /* ksvc.class.kafkaTopics renders one topic CR per distinct source or bucket-notification topic. */ -}}
{{- define "ksvc.class.kafkaTopics" -}}
{{- $cluster := .Values.kafka.cluster -}}
{{- if and $cluster.enabled $cluster.topics.create -}}
{{- $topics := dict -}}
{{- range $key, $source := .Values.kafka.sources -}}
{{- if $source.topic -}}
{{- $_ := set $topics $source.topic true -}}
{{- end -}}
{{- end -}}
{{- range $bucketKey, $bucket := .Values.objectBuckets -}}
{{- $notifications := $bucket.notifications | default dict -}}
{{- range $eventKey, $notification := $notifications -}}
{{- if $notification.enabled -}}
{{- $topicName := include "ksvc.objectBucketNotificationTopicName" (dict "root" $ "bucketKey" $bucketKey "eventKey" $eventKey) -}}
{{- $_ := set $topics $topicName true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $first := true -}}
{{- range $topic, $_ := $topics -}}
{{- if not $first }}
---
{{ end -}}
{{- $first = false -}}
{{- if eq $cluster.provider "redpanda" -}}
{{- include "ksvc.class.kafkaRedpandaTopic" (dict "root" $ "topic" $topic) -}}
{{- else -}}
{{- include "ksvc.class.kafkaStrimziTopic" (dict "root" $ "topic" $topic "name" (include "ksvc.kafkaTopicName" $topic)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
