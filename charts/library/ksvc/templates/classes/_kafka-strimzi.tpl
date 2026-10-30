{{- /* Strimzi provider: KafkaNodePool + Kafka, KafkaTopic, and SCRAM KafkaUser. */ -}}
{{- define "ksvc.class.kafkaStrimzi" -}}
{{- $cluster := .Values.kafka.cluster -}}
{{- $name := include "ksvc.kafkaClusterName" . -}}
{{- $storageClass := $cluster.storage.storageClassName | default "" -}}
{{- $volume := dict "id" 0 "type" "persistent-claim" "size" $cluster.storage.size "deleteClaim" false "kraftMetadata" "shared" -}}
{{- if $storageClass -}}
{{- $_ := set $volume "class" $storageClass -}}
{{- end -}}
{{- $nodePoolSpec := dict
  "replicas" (int $cluster.replicas)
  "roles" (list "controller" "broker")
  "storage" (dict "type" "jbod" "volumes" (list $volume))
  "resources" $cluster.resources
-}}
{{- $nodePoolExtra := $cluster.strimzi.nodePoolExtraSpec | default dict -}}
{{- $nodePoolSpec = mustMergeOverwrite (deepCopy $nodePoolSpec) $nodePoolExtra -}}
{{- $authType := $cluster.auth.type | default "none" -}}
{{- $plain := dict "name" "plain" "port" 9092 "type" "internal" "tls" false -}}
{{- $listeners := list $plain -}}
{{- if $cluster.tls.enabled -}}
{{- $tlsListener := dict "name" "tls" "port" 9093 "type" "internal" "tls" true -}}
{{- $listeners = append $listeners $tlsListener -}}
{{- end -}}
{{- if eq $authType "scram" -}}
{{- $auth := dict "type" "scram-sha-512" -}}
{{- range $listener := $listeners -}}
{{- $_ := set $listener "authentication" (deepCopy $auth) -}}
{{- end -}}
{{- end -}}
{{- $replicationFactor := int (include "ksvc.kafkaTopicReplicationFactor" .) -}}
{{- $minInSyncReplicas := int (include "ksvc.kafkaMinInSyncReplicas" .) -}}
{{- $config := dict
  "offsets.topic.replication.factor" $replicationFactor
  "transaction.state.log.replication.factor" $replicationFactor
  "transaction.state.log.min.isr" $minInSyncReplicas
  "default.replication.factor" $replicationFactor
  "min.insync.replicas" $minInSyncReplicas
-}}
{{- $kafkaSpec := dict "listeners" $listeners "config" $config -}}
{{- $version := $cluster.strimzi.version | default "" -}}
{{- if $version -}}
{{- $_ := set $kafkaSpec "version" $version -}}
{{- end -}}
{{- $metadataVersion := $cluster.strimzi.metadataVersion | default "" -}}
{{- if $metadataVersion -}}
{{- $_ := set $kafkaSpec "metadataVersion" $metadataVersion -}}
{{- end -}}
{{- if eq $authType "scram" -}}
{{- $_ := set $kafkaSpec "authorization" (dict "type" "simple") -}}
{{- end -}}
{{- $spec := dict
  "kafka" $kafkaSpec
  "entityOperator" (dict "topicOperator" (dict) "userOperator" (dict))
-}}
{{- $extraSpec := $cluster.strimzi.extraSpec | default dict -}}
{{- $spec = mustMergeOverwrite (deepCopy $spec) $extraSpec -}}
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: {{ printf "%s-dual-role" $name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    strimzi.io/cluster: {{ $name }}
spec:
  {{- toYaml $nodePoolSpec | nindent 2 }}
---
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata:
  name: {{ $name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
spec:
  {{- toYaml $spec | nindent 2 }}
{{- end }}

{{- define "ksvc.class.kafkaStrimziTopic" -}}{{- end }}

{{- define "ksvc.class.kafkaStrimziUser" -}}{{- end }}
