{{/*
ksvc.class.objectBucketNotification — Render a CephBucketTopic and
CephBucketNotification for one enabled bucket notification. The corresponding
Kafka topic is rendered by ksvc.class.kafkaTopics.
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
      useSSL: false
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
  {{- $filter := $notification.filter | default dict -}}
  {{- if or $filter.keyFilters $filter.metadataFilters $filter.tagFilters }}
  filter:
    {{- with $filter.keyFilters }}
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
