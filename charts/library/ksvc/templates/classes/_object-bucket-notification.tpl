{{/*
ksvc.class.objectBucketNotification — Render a CephBucketTopic and
CephBucketNotification for one enabled bucket notification. The corresponding
Kafka topic and KafkaSource are rendered by ksvc.class.kafkaTopics and the
synthetic kafka.sources entries built in ksvc.loader.applyDefaults.
Expects context: dict with "root", "bucketKey", "eventKey", "bucket", and
"notification".
*/}}
{{- define "ksvc.class.objectBucketNotification" -}}
{{- $root := .root -}}
{{- $bucket := .bucket -}}
{{- $notification := .notification -}}
{{- $eventMap := dict
  "put" "s3:ObjectCreated:Put"
  "post" "s3:ObjectCreated:Post"
  "copy" "s3:ObjectCreated:Copy"
  "multipart" "s3:ObjectCreated:CompleteMultipartUpload"
  "delete" "s3:ObjectRemoved:Delete"
  "delete-marker" "s3:ObjectRemoved:DeleteMarkerCreated"
-}}
{{- $event := index $eventMap .eventKey -}}
{{- $topicName := include "ksvc.objectBucketNotificationTopicName" (dict "root" $root "bucketKey" .bucketKey "eventKey" .eventKey) -}}
{{- $notificationName := include "ksvc.objectBucketNotificationName" (dict "root" $root "bucketKey" .bucketKey "eventKey" .eventKey) -}}
{{- $kafkaURI := printf "kafka://%s" (include "ksvc.kafkaBootstrapServers" $root) -}}
{{- $tlsEnabled := $root.Values.kafka.cluster.tls.enabled -}}
{{- $filter := $notification.filter | default dict -}}
{{- $keyFilters := list -}}
{{- if $notification.prefix -}}
{{- $keyFilters = append $keyFilters (dict "name" "prefix" "value" $notification.prefix) -}}
{{- end -}}
{{- if $notification.suffix -}}
{{- $keyFilters = append $keyFilters (dict "name" "suffix" "value" $notification.suffix) -}}
{{- end -}}
{{- range $keyFilter := ($filter.keyFilters | default list) -}}
{{- $keyFilters = append $keyFilters $keyFilter -}}
{{- end -}}
apiVersion: ceph.rook.io/v1
kind: CephBucketTopic
metadata:
  name: {{ $topicName }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" $root | nindent 4 }}
    app.kubernetes.io/component: object-bucket-notification
  {{- $globalAnnotations := include "ksvc.annotations" $root -}}
  {{- with $globalAnnotations }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  objectStoreName: {{ $bucket.objectStore.name | quote }}
  objectStoreNamespace: {{ $bucket.objectStore.namespace | quote }}
  persistent: {{ $notification.persistent }}
  {{- with $notification.opaqueData }}
  opaqueData: {{ . | quote }}
  {{- end }}
  endpoint:
    kafka:
      uri: {{ $kafkaURI | quote }}
      ackLevel: {{ $notification.ackLevel | default "broker" | quote }}
      useSSL: {{ $tlsEnabled }}
      {{- if $tlsEnabled }}
      disableVerifySSL: true
      {{- end }}
---
apiVersion: ceph.rook.io/v1
kind: CephBucketNotification
metadata:
  name: {{ $notificationName }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" $root | nindent 4 }}
    app.kubernetes.io/component: object-bucket-notification
  {{- $globalAnnotations := include "ksvc.annotations" $root -}}
  {{- with $globalAnnotations }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
spec:
  topic: {{ $topicName | quote }}
  events:
    - {{ $event | quote }}
  {{- if or $keyFilters $filter.metadataFilters $filter.tagFilters }}
  filter:
    {{- with $keyFilters }}
    keyFilters:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $filter.metadataFilters }}
    metadataFilters:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $filter.tagFilters }}
    tagFilters:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- end }}
{{- end }}
