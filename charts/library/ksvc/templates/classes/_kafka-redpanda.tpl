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

{{- define "ksvc.class.kafkaRedpandaTopic" -}}{{- end }}
{{- define "ksvc.class.kafkaRedpandaUser" -}}{{- end }}
