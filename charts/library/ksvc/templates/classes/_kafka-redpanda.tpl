{{/*
ksvc.class.kafkaRedpanda — Render the managed Redpanda cluster.

Context: root. Renders one cluster.redpanda.com/v1alpha2 Redpanda CR. The
chart-level `kafka.cluster.redpanda.extraClusterSpec` is merged into
`spec.clusterSpec` last (consumer values win) and is never emitted as a key.
*/}}
{{- define "ksvc.class.kafkaRedpanda" -}}
{{- $cluster := .Values.kafka.cluster -}}
{{- $name := include "ksvc.kafkaClusterName" . -}}
{{- $replicas := int $cluster.replicas -}}

{{/* CPU request -> Redpanda `resources.cpu.cores` (ceil of whole cores). */}}
{{- $cpuRaw := toString $cluster.resources.requests.cpu -}}
{{- $cores := 1 -}}
{{- if hasSuffix "m" $cpuRaw -}}
{{- $millis := int (trimSuffix "m" $cpuRaw) -}}
{{- $cores = div (add $millis 999) 1000 -}}
{{- else -}}
{{- $cores = int (ceil (float64 $cpuRaw)) -}}
{{- end -}}

{{- $persistentVolume := dict "enabled" true "size" (toString $cluster.storage.size) -}}
{{- if $cluster.storage.storageClassName -}}
{{- $_ := set $persistentVolume "storageClass" $cluster.storage.storageClassName -}}
{{- end -}}

{{- $kafkaListener := dict "port" 9093 "tls" (dict "enabled" $cluster.tls.enabled) -}}
{{- if eq $cluster.auth.type "scram" -}}
{{- $_ := set $kafkaListener "authenticationMethod" "sasl" -}}
{{- end -}}

{{- $clusterSpec := dict -}}
{{- $_ := set $clusterSpec "statefulset" (dict "replicas" $replicas) -}}
{{- $_ := set $clusterSpec "storage" (dict "persistentVolume" $persistentVolume) -}}
{{- $_ := set $clusterSpec "resources" (dict
      "cpu" (dict "cores" $cores)
      "memory" (dict "container" (dict
        "min" (toString $cluster.resources.requests.memory)
        "max" (toString $cluster.resources.limits.memory)))) -}}
{{- $_ := set $clusterSpec "listeners" (dict "kafka" $kafkaListener) -}}
{{- $_ := set $clusterSpec "tls" (dict "enabled" $cluster.tls.enabled) -}}
{{- if eq $cluster.auth.type "scram" -}}
{{- $sasl := dict "enabled" true -}}
{{- if $cluster.redpanda.sasl.secretRef -}}
{{- $_ := set $sasl "secretRef" $cluster.redpanda.sasl.secretRef -}}
{{- end -}}
{{- $_ := set $clusterSpec "auth" (dict "sasl" $sasl) -}}
{{- end -}}
{{- if ge $replicas 3 -}}
{{- $_ := set $clusterSpec "config" (dict "redpanda" (dict "default_topic_replications" 3)) -}}
{{- end -}}
{{- $_ := set $clusterSpec "external" (dict "enabled" false) -}}

{{- $extraClusterSpec := $cluster.redpanda.extraClusterSpec | default dict -}}
{{- if $extraClusterSpec -}}
{{- $_ := mustMergeOverwrite $clusterSpec $extraClusterSpec -}}
{{- end -}}
apiVersion: cluster.redpanda.com/v1alpha2
kind: Redpanda
metadata:
  name: {{ $name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
spec:
  clusterSpec:
    {{- toYaml $clusterSpec | nindent 4 }}
{{- end }}

{{/*
ksvc.class.kafkaRedpandaTopic — Render one managed Kafka topic.

Context: dict "root" $ "topic" <raw topic name>. The topic is emitted verbatim
because validators require a DNS-1123 subdomain for Redpanda topics.
*/}}
{{- define "ksvc.class.kafkaRedpandaTopic" -}}
{{- $root := .root -}}
{{- $cluster := $root.Values.kafka.cluster -}}
apiVersion: cluster.redpanda.com/v1alpha2
kind: Topic
metadata:
  name: {{ .topic }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" $root | nindent 4 }}
spec:
  cluster:
    clusterRef:
      name: {{ include "ksvc.kafkaClusterName" $root }}
  partitions: {{ int $cluster.topics.partitions }}
  replicationFactor: {{ int (include "ksvc.kafkaTopicReplicationFactor" $root) }}
{{- end }}

{{/*
ksvc.class.kafkaRedpandaUser — Render the managed SCRAM user and its ACLs.

Context: root. The operator creates/adopts the password Secret, so the chart
never renders it. One topic ACL is emitted per distinct source topic and one
group ACL per distinct effective consumer group.
*/}}
{{- define "ksvc.class.kafkaRedpandaUser" -}}
{{- $topics := dict -}}
{{- $groups := dict -}}
{{- range $key, $source := .Values.kafka.sources -}}
{{- $_ := set $topics $source.topic true -}}
{{- $group := default (include "ksvc.kafkaConsumerGroup" (dict "root" $ "key" $key)) $source.consumerGroup -}}
{{- $_ := set $groups $group true -}}
{{- end -}}
{{- $acls := list -}}
{{- range $topic, $_ := $topics -}}
{{- $acls = append $acls (dict
      "type" "allow"
      "resource" (dict "type" "topic" "name" $topic "patternType" "literal")
      "operations" (list "Read" "Describe" "Write")
      "host" "*") -}}
{{- end -}}
{{- range $group, $_ := $groups -}}
{{- $acls = append $acls (dict
      "type" "allow"
      "resource" (dict "type" "group" "name" $group "patternType" "literal")
      "operations" (list "Read")
      "host" "*") -}}
{{- end -}}
apiVersion: cluster.redpanda.com/v1alpha2
kind: User
metadata:
  name: {{ include "ksvc.kafkaUserName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
spec:
  cluster:
    clusterRef:
      name: {{ include "ksvc.kafkaClusterName" . }}
  authentication:
    type: scram-sha-512
    password:
      valueFrom:
        secretKeyRef:
          name: {{ include "ksvc.kafkaUserSecretName" . }}
          key: password
  authorization:
    type: simple
    acls:
      {{- toYaml $acls | nindent 6 }}
{{- end }}
