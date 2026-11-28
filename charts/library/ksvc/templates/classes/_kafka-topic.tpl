{{- /* ksvc.class.kafkaTopics renders one topic CR per distinct source or bucket-notification topic. */ -}}
{{- define "ksvc.class.kafkaTopics" -}}
{{- $cluster := .Values.kafka.cluster -}}
{{- if and $cluster.enabled $cluster.topics.create -}}
{{- $topics := dict -}}
{{- range $key, $source := .Values.kafka.sources -}}
{{- if $source.topic -}}
{{- $partitions := int ($source.partitions | default 0) -}}
{{- if lt $partitions 1 -}}
{{- $partitions = int $cluster.topics.partitions -}}
{{- end -}}
{{- $_ := set $topics $source.topic $partitions -}}
{{- end -}}
{{- end -}}
{{- range $bucketKey, $bucket := .Values.objectBuckets -}}
{{- $notifications := $bucket.notifications | default dict -}}
{{- $events := $notifications.events | default dict -}}
{{- if not $events -}}
{{- $events = $notifications -}}
{{- end -}}
{{- range $eventKey, $notification := $events -}}
{{- if and (kindIs "map" $notification) ($notification.enabled) -}}
{{- $topicName := include "ksvc.objectBucketNotificationTopicName" (dict "root" $ "bucketKey" $bucketKey "eventKey" $eventKey) -}}
{{- $partitions := int ($notification.partitions | default 0) -}}
{{- if lt $partitions 1 -}}
{{- $partitions = int $cluster.topics.partitions -}}
{{- end -}}
{{- $_ := set $topics $topicName $partitions -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $first := true -}}
{{- range $topic, $partitions := $topics -}}
{{- if not $first }}
---
{{ end -}}
{{- $first = false -}}
{{- if eq $cluster.provider "redpanda" -}}
{{- include "ksvc.class.kafkaRedpandaTopic" (dict "root" $ "topic" $topic "partitions" $partitions) -}}
{{- else -}}
{{- include "ksvc.class.kafkaStrimziTopic" (dict "root" $ "topic" $topic "partitions" $partitions "name" (include "ksvc.kafkaTopicName" $topic)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
