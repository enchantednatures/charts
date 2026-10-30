{{/*
Validate required values at template render time.
Call this from the loader to catch misconfigurations early.
*/}}
{{- define "ksvc.validate" -}}
  {{/* services map must exist and have at least one entry */}}
  {{- if not .Values.services -}}
    {{- fail "services is required and must contain at least one service entry" -}}
  {{- end -}}
  {{- if not (kindIs "map" .Values.services) -}}
    {{- fail "services must be a map (e.g. services: { api: { ... } })" -}}
  {{- end -}}
  {{- if eq (len .Values.services) 0 -}}
    {{- fail "services must contain at least one service entry" -}}
  {{- end -}}

  {{/* each service must have image.repository */}}
  {{- range $key, $svc := .Values.services -}}
    {{- if not $svc.image -}}
      {{- fail (printf "services.%s.image is required" $key) -}}
    {{- end -}}
    {{- if not $svc.image.repository -}}
      {{- fail (printf "services.%s.image.repository is required" $key) -}}
    {{- end -}}
    {{/* scaling must be a map; a nil/non-map cannot render and must fail cleanly */}}
    {{- if not (kindIs "map" $svc.scaling) -}}
      {{- fail (printf "services.%s.scaling must be a map (got %v)" $key $svc.scaling) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.minScale "path" (printf "services.%s.scaling.minScale" $key)) -}}
    {{- $minScale := int $svc.scaling.minScale -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.maxScale "path" (printf "services.%s.scaling.maxScale" $key)) -}}
    {{- $maxScale := int $svc.scaling.maxScale -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.target "path" (printf "services.%s.scaling.target" $key)) -}}
    {{- $target := int $svc.scaling.target -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.containerConcurrency "path" (printf "services.%s.scaling.containerConcurrency" $key)) -}}
    {{- $containerConcurrency := int $svc.scaling.containerConcurrency -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.scaling.timeoutSeconds "path" (printf "services.%s.scaling.timeoutSeconds" $key)) -}}
    {{- $timeoutSeconds := int $svc.scaling.timeoutSeconds -}}
    {{- if lt $minScale 0 -}}
      {{- fail (printf "services.%s.scaling.minScale must be >= 0 (got %d)" $key $minScale) -}}
    {{- end -}}
    {{- if lt $maxScale 1 -}}
      {{- fail (printf "services.%s.scaling.maxScale must be >= 1 (got %d)" $key $maxScale) -}}
    {{- end -}}
    {{- if gt $minScale $maxScale -}}
      {{- fail (printf "services.%s.scaling: minScale (%d) must be <= maxScale (%d)" $key $minScale $maxScale) -}}
    {{- end -}}
    {{- if lt $target 1 -}}
      {{- fail (printf "services.%s.scaling.target must be >= 1 (got %d)" $key $target) -}}
    {{- end -}}
    {{- if lt $containerConcurrency 0 -}}
      {{- fail (printf "services.%s.scaling.containerConcurrency must be >= 0 (got %d)" $key $containerConcurrency) -}}
    {{- end -}}
    {{- if lt $timeoutSeconds 1 -}}
      {{- fail (printf "services.%s.scaling.timeoutSeconds must be >= 1 (got %d)" $key $timeoutSeconds) -}}
    {{- end -}}
    {{/* workload validation (Knative default, or standard Deployment work-alike) */}}
    {{- if not (has $svc.workload.type (list "Knative" "Deployment")) -}}
      {{- fail (printf "services.%s.workload.type must be one of Knative|Deployment (got %v)" $key $svc.workload.type) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.workload.replicas "path" (printf "services.%s.workload.replicas" $key)) -}}
    {{- $replicas := int $svc.workload.replicas -}}
    {{- if lt $replicas 1 -}}
      {{- fail (printf "services.%s.workload.replicas must be >= 1 (got %d)" $key $replicas) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.workload.terminationGracePeriodSeconds "path" (printf "services.%s.workload.terminationGracePeriodSeconds" $key)) -}}
    {{- $terminationGracePeriodSeconds := int $svc.workload.terminationGracePeriodSeconds -}}
    {{- if lt $terminationGracePeriodSeconds 0 -}}
      {{- fail (printf "services.%s.workload.terminationGracePeriodSeconds must be >= 0 (got %d)" $key $terminationGracePeriodSeconds) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $svc.workload.preStopSleepSeconds "path" (printf "services.%s.workload.preStopSleepSeconds" $key)) -}}
    {{- $preStopSleepSeconds := int $svc.workload.preStopSleepSeconds -}}
    {{- if lt $preStopSleepSeconds 0 -}}
      {{- fail (printf "services.%s.workload.preStopSleepSeconds must be >= 0 (got %d)" $key $preStopSleepSeconds) -}}
    {{- end -}}
    {{- if and (gt $preStopSleepSeconds 0) (gt $terminationGracePeriodSeconds 0) (ge $preStopSleepSeconds $terminationGracePeriodSeconds) -}}
      {{- fail (printf "services.%s.workload.preStopSleepSeconds (%d) must be < terminationGracePeriodSeconds (%d)" $key $preStopSleepSeconds $terminationGracePeriodSeconds) -}}
    {{- end -}}
    {{- if and $svc.podDisruptionBudget.enabled (ne $svc.workload.type "Deployment") -}}
      {{- fail (printf "services.%s.podDisruptionBudget.enabled requires workload.type: Deployment" $key) -}}
    {{- end -}}
    {{- if eq $svc.workload.type "Deployment" -}}
      {{- if and $svc.flagger $svc.flagger.enabled -}}
        {{- fail (printf "services.%s: flagger.enabled is not supported with workload.type: Deployment (the flagger Canary class targets Knative Services)" $key) -}}
      {{- end -}}
      {{- if not (has $svc.service.type (list "ClusterIP" "NodePort" "LoadBalancer")) -}}
        {{- fail (printf "services.%s.service.type must be one of ClusterIP|NodePort|LoadBalancer (got %v)" $key $svc.service.type) -}}
      {{- end -}}
      {{- include "ksvc.validate.requireInteger" (dict "value" $svc.service.port "path" (printf "services.%s.service.port" $key)) -}}
      {{- $servicePort := int $svc.service.port -}}
      {{- if or (lt $servicePort 1) (gt $servicePort 65535) -}}
        {{- fail (printf "services.%s.service.port must be between 1 and 65535 (got %d)" $key $servicePort) -}}
      {{- end -}}
      {{- if not (has $svc.service.sessionAffinity (list "None" "ClientIP")) -}}
        {{- fail (printf "services.%s.service.sessionAffinity must be one of None|ClientIP (got %v)" $key $svc.service.sessionAffinity) -}}
      {{- end -}}
      {{- include "ksvc.validate.requireInteger" (dict "value" $svc.service.sessionAffinityConfig.clientIP.timeoutSeconds "path" (printf "services.%s.service.sessionAffinityConfig.clientIP.timeoutSeconds" $key)) -}}
      {{- $sessionAffinityTimeout := int $svc.service.sessionAffinityConfig.clientIP.timeoutSeconds -}}
      {{- if or (lt $sessionAffinityTimeout 1) (gt $sessionAffinityTimeout 86400) -}}
        {{- fail (printf "services.%s.service.sessionAffinityConfig.clientIP.timeoutSeconds must be between 1 and 86400 (got %d)" $key $sessionAffinityTimeout) -}}
      {{- end -}}
      {{- if not (has $svc.service.externalTrafficPolicy (list "" "Cluster" "Local")) -}}
        {{- fail (printf "services.%s.service.externalTrafficPolicy must be one of \"\", Cluster, Local (got %v)" $key $svc.service.externalTrafficPolicy) -}}
      {{- end -}}
      {{- if and $svc.service.externalTrafficPolicy (eq $svc.service.type "ClusterIP") -}}
        {{- fail (printf "services.%s.service.externalTrafficPolicy (%v) requires service.type NodePort or LoadBalancer (got ClusterIP)" $key $svc.service.externalTrafficPolicy) -}}
      {{- end -}}
      {{- if $svc.podDisruptionBudget.enabled -}}
        {{- $pdbMin := $svc.podDisruptionBudget.minAvailable -}}
        {{- $pdbMax := $svc.podDisruptionBudget.maxUnavailable -}}
        {{- if and $pdbMin $pdbMax -}}
          {{- fail (printf "services.%s.podDisruptionBudget: minAvailable and maxUnavailable are mutually exclusive — set one of them to 0" $key) -}}
        {{- end -}}
        {{- if and (not $pdbMin) (not $pdbMax) -}}
          {{- fail (printf "services.%s.podDisruptionBudget: exactly one of minAvailable or maxUnavailable must be set when enabled" $key) -}}
        {{- end -}}
        {{- if and $pdbMin (not (kindIs "string" $pdbMin)) (gt (int $pdbMin) $replicas) -}}
          {{- fail (printf "services.%s.podDisruptionBudget.minAvailable (%d) must be <= workload.replicas (%d)" $key (int $pdbMin) $replicas) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* objectBuckets entry validation (runs after applyDefaults).
       Per-entry check order is fixed (storageClassName, key, bucketName) so the
       failure message is deterministic. */}}
  {{- if .Values.objectBuckets -}}
    {{- range $key, $bucket := .Values.objectBuckets -}}
      {{- if not $bucket.storageClassName -}}
        {{- fail (printf "objectBuckets.%s.storageClassName is required and must name an existing bucket StorageClass" $key) -}}
      {{- end -}}
      {{- if or (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $key)) (gt (len $key) 53) -}}
        {{- fail (printf "objectBuckets.%s must be a DNS-1123 label" $key) -}}
      {{- end -}}
      {{- if not (regexMatch "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$" $bucket.bucketName) -}}
        {{- fail (printf "objectBuckets.%s.bucketName must be a valid S3 bucket name (3-63 chars, lowercase letters, digits, dots, hyphens)" $key) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* postgres backup validation */}}
  {{- if and .Values.postgres.enabled .Values.postgres.backup.enabled (not .Values.postgres.backup.objectStore.destinationPath) -}}
    {{- fail "postgres.backup.objectStore.destinationPath is required when postgres backup is enabled" -}}
  {{- end -}}
  {{- if and .Values.postgres.enabled .Values.postgres.backup.enabled (not .Values.postgres.backup.objectStore.endpointURL) -}}
    {{- fail "postgres.backup.objectStore.endpointURL is required when postgres backup is enabled" -}}
  {{- end -}}
  {{/* postgres backup bucketRef validation (defensive read: the key may not exist yet if todo 5 has not landed) */}}
  {{- $pgBucketRef := .Values.postgres.backup.objectStore.bucketRef | default "" -}}
  {{- if $pgBucketRef -}}
    {{- if and .Values.postgres.backup.enabled (not (hasKey .Values.objectBuckets $pgBucketRef)) -}}
      {{- fail (printf "postgres.backup.objectStore.bucketRef references '%s' which does not exist in objectBuckets" $pgBucketRef) -}}
    {{- end -}}
    {{- if not .Values.postgres.backup.enabled -}}
      {{- fail "postgres.backup.objectStore.bucketRef is set but postgres.backup.enabled is false" -}}
    {{- end -}}
  {{- end -}}

  {{/* postgres instance count validation */}}
  {{- if .Values.postgres.enabled -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" .Values.postgres.instances "path" "postgres.instances") -}}
    {{- $pgInstances := int .Values.postgres.instances -}}
    {{- if or (lt $pgInstances 1) (gt $pgInstances 16) -}}
      {{- fail (printf "postgres.instances must be >= 1 and <= 16 (got %d)" $pgInstances) -}}
    {{- end -}}
    {{- if .Values.postgres.pooler.enabled -}}
      {{- include "ksvc.validate.requireInteger" (dict "value" .Values.postgres.pooler.instances "path" "postgres.pooler.instances") -}}
      {{- $poolerInstances := int .Values.postgres.pooler.instances -}}
      {{- if lt $poolerInstances 1 -}}
        {{- fail (printf "postgres.pooler.instances must be >= 1 (got %d)" $poolerInstances) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- /* kafka broker, source, and trigger validation */ -}}
  {{- $hasBroker := and .Values.kafka .Values.kafka.broker .Values.kafka.broker.enabled -}}
  {{- $cluster := .Values.kafka.cluster | default dict -}}
  {{- if $cluster.enabled -}}
    {{- if not (has $cluster.provider (list "strimzi" "redpanda")) -}}
      {{- fail (printf "kafka.cluster.provider must be one of strimzi, redpanda (got %v)" $cluster.provider) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $cluster.replicas "path" "kafka.cluster.replicas") -}}
    {{- $clusterReplicas := int $cluster.replicas -}}
    {{- if or (lt $clusterReplicas 1) (gt $clusterReplicas 16) -}}
      {{- fail (printf "kafka.cluster.replicas must be >= 1 and <= 16 (got %d)" $clusterReplicas) -}}
    {{- end -}}
    {{- if and $cluster.name (gt (len $cluster.name) 48) -}}
      {{- fail (printf "kafka.cluster.name must be <= 48 characters so derived Service names stay <= 63 (got %d)" (len $cluster.name)) -}}
    {{- end -}}
    {{- if not (has $cluster.auth.type (list "none" "scram")) -}}
      {{- fail (printf "kafka.cluster.auth.type must be one of none, scram (got %v)" $cluster.auth.type) -}}
    {{- end -}}
    {{- if and $cluster.auth.username (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $cluster.auth.username)) -}}
      {{- fail (printf "kafka.cluster.auth.username must be a DNS-1123 label (got %v)" $cluster.auth.username) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" $cluster.topics.partitions "path" "kafka.cluster.topics.partitions") -}}
    {{- if lt (int $cluster.topics.partitions) 1 -}}
      {{- fail (printf "kafka.cluster.topics.partitions must be >= 1 (got %d)" (int $cluster.topics.partitions)) -}}
    {{- end -}}
    {{- if and (eq $cluster.provider "redpanda") (eq $cluster.auth.type "scram") (not $cluster.redpanda.sasl.secretRef) -}}
      {{- fail "kafka.cluster.redpanda.sasl.secretRef is required when kafka.cluster.auth.type=scram for Redpanda — provide a superuser Secret in users.txt format" -}}
    {{- end -}}
    {{- if and $hasBroker (or (eq $cluster.auth.type "scram") $cluster.tls.enabled) (not .Values.kafka.broker.config.authSecretName) -}}
      {{- fail "kafka.broker.config.authSecretName is required when kafka.broker.enabled=true and the managed cluster uses SCRAM or TLS — the Broker needs a Secret with sasl.mechanism, user, password, security.protocol (and ca.crt for TLS)" -}}
    {{- end -}}
    {{- $topicNames := dict -}}
    {{- range $key, $source := .Values.kafka.sources -}}
      {{- if eq $cluster.provider "redpanda" -}}
        {{- if not (regexMatch "^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$" $source.topic) -}}
          {{- fail (printf "kafka.sources.%s.topic must be a DNS-1123 subdomain for Redpanda (got %v)" $key $source.topic) -}}
        {{- end -}}
      {{- else -}}
        {{- $sanitized := include "ksvc.kafkaTopicName" $source.topic -}}
        {{- if hasKey $topicNames $sanitized -}}
          {{- if ne (index $topicNames $sanitized) $source.topic -}}
            {{- fail (printf "kafka.sources.%s.topic sanitizes to '%s', which collides with topic '%s'" $key $sanitized (index $topicNames $sanitized)) -}}
          {{- end -}}
        {{- else -}}
          {{- $_ := set $topicNames $sanitized $source.topic -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if $hasBroker -}}
    {{- if not (kindIs "map" .Values.kafka.broker.config) -}}
      {{- fail "kafka.broker.config must be a map" -}}
    {{- end -}}
    {{- if not .Values.kafka.broker.config.bootstrapServers -}}
      {{- fail "kafka.broker.config.bootstrapServers must contain at least one server when kafka.broker.enabled=true" -}}
    {{- end -}}
    {{- if .Values.kafka.broker.delivery.deadLetterSink.enabled -}}
      {{- if and (not .Values.kafka.broker.delivery.deadLetterSink.uri) (not .Values.kafka.broker.delivery.deadLetterSink.ref.name) -}}
        {{- fail "kafka.broker.delivery.deadLetterSink requires either uri or ref.name when enabled" -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- /* kafka source sink validation */ -}}
  {{- if and .Values.kafka .Values.kafka.sources -}}
    {{- range $key, $source := .Values.kafka.sources -}}
      {{- if $hasBroker -}}
        {{- if $source.sink -}}
          {{- fail (printf "kafka.sources.%s.sink must not be set when kafka.broker.enabled=true — sources sink to the broker; remove sink or disable the broker" $key) -}}
        {{- end -}}
      {{- else -}}
        {{- if not $source.sink -}}
          {{- fail (printf "kafka.sources.%s.sink is required and must reference a key in the services map" $key) -}}
        {{- end -}}
        {{- if not (hasKey $.Values.services $source.sink) -}}
          {{- fail (printf "kafka.sources.%s.sink references '%s' which does not exist in the services map" $key $source.sink) -}}
        {{- end -}}
        {{/* a Deployment-backed service exposes no Knative addressable, so it cannot be a Kafka sink */}}
        {{- if eq (index $.Values.services $source.sink).workload.type "Deployment" -}}
          {{- fail (printf "kafka.sources.%s.sink references '%s' which uses workload.type: Deployment — a plain Kubernetes Service is not a Knative-addressable sink; point the sink at a Knative service" $key $source.sink) -}}
        {{- end -}}
      {{- end -}}
      {{/* DLQ scaling validation (only when the DLQ is enabled) */}}
      {{- if and $source.dlq $source.dlq.enabled -}}
        {{- if not (kindIs "map" $source.dlq.scaling) -}}
          {{- fail (printf "kafka.sources.%s.dlq.scaling must be a map (got %v)" $key $source.dlq.scaling) -}}
        {{- end -}}
        {{- include "ksvc.validate.requireInteger" (dict "value" $source.dlq.scaling.minScale "path" (printf "kafka.sources.%s.dlq.scaling.minScale" $key)) -}}
        {{- $dlqMinScale := int $source.dlq.scaling.minScale -}}
        {{- include "ksvc.validate.requireInteger" (dict "value" $source.dlq.scaling.maxScale "path" (printf "kafka.sources.%s.dlq.scaling.maxScale" $key)) -}}
        {{- $dlqMaxScale := int $source.dlq.scaling.maxScale -}}
        {{- if lt $dlqMinScale 0 -}}
          {{- fail (printf "kafka.sources.%s.dlq.scaling.minScale must be >= 0 (got %d)" $key $dlqMinScale) -}}
        {{- end -}}
        {{- if lt $dlqMaxScale 1 -}}
          {{- fail (printf "kafka.sources.%s.dlq.scaling.maxScale must be >= 1 (got %d)" $key $dlqMaxScale) -}}
        {{- end -}}
        {{- if gt $dlqMinScale $dlqMaxScale -}}
          {{- fail (printf "kafka.sources.%s.dlq.scaling: minScale (%d) must be <= maxScale (%d)" $key $dlqMinScale $dlqMaxScale) -}}
        {{- end -}}
      {{- end -}}
      {{/* KafkaSource TLS/SASL validation */}}
      {{- $net := $source.net | default dict -}}
      {{- $tls := $net.tls | default dict -}}
      {{- $sasl := $net.sasl | default dict -}}
      {{- $managed := and $.Values.kafka $.Values.kafka.cluster $.Values.kafka.cluster.enabled -}}
      {{- if $managed -}}
        {{- if and (eq $cluster.auth.type "scram") (not $sasl.enabled) -}}
          {{- fail (printf "kafka.sources.%s.net.sasl.enabled must be true when kafka.cluster.auth.type=scram" $key) -}}
        {{- end -}}
        {{- if and (eq $cluster.provider "redpanda") $cluster.tls.enabled (not $tls.enabled) -}}
          {{- fail (printf "kafka.sources.%s.net.tls.enabled must be true when kafka.cluster.provider=redpanda and kafka.cluster.tls.enabled=true" $key) -}}
        {{- end -}}
      {{- end -}}
      {{- if $tls.enabled -}}
        {{- if and (not $tls.caCertSecret) (not $managed) -}}
          {{- fail (printf "kafka.sources.%s.net.tls.caCertSecret is required when net.tls.enabled=true and kafka.cluster is not enabled" $key) -}}
        {{- end -}}
        {{- if not $sasl.enabled -}}
          {{- if not $tls.certSecret -}}
            {{- fail (printf "kafka.sources.%s.net.tls.certSecret is required for TLS-only (mTLS) KafkaSource; set net.sasl.enabled=true for SASL_SSL or provide certSecret/keySecret" $key) -}}
          {{- end -}}
          {{- if not $tls.keySecret -}}
            {{- fail (printf "kafka.sources.%s.net.tls.keySecret is required for TLS-only (mTLS) KafkaSource; set net.sasl.enabled=true for SASL_SSL or provide certSecret/keySecret" $key) -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
      {{- if $sasl.enabled -}}
        {{- $mechanisms := list "PLAIN" "SCRAM-SHA-256" "SCRAM-SHA-512" -}}
        {{- if not (has $sasl.mechanism $mechanisms) -}}
          {{- fail (printf "kafka.sources.%s.net.sasl.mechanism must be one of PLAIN, SCRAM-SHA-256, SCRAM-SHA-512 (got %v)" $key $sasl.mechanism) -}}
        {{- end -}}
        {{- if not $managed -}}
          {{- if not $sasl.userSecret -}}
            {{- fail (printf "kafka.sources.%s.net.sasl.userSecret is required for external SASL; set kafka.cluster.enabled=true for managed credentials" $key) -}}
          {{- end -}}
          {{- if not $sasl.passwordSecret -}}
            {{- fail (printf "kafka.sources.%s.net.sasl.passwordSecret is required for external SASL; set kafka.cluster.enabled=true for managed credentials" $key) -}}
          {{- end -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{- /* kafka trigger validation */ -}}
  {{- if and .Values.kafka .Values.kafka.triggers -}}
    {{- if not $hasBroker -}}
      {{- fail "kafka.triggers requires kafka.broker.enabled=true — triggers route events from the broker to services" -}}
    {{- end -}}
    {{- range $key, $trigger := .Values.kafka.triggers -}}
      {{- if not $trigger.subscriber -}}
        {{- fail (printf "kafka.triggers.%s.subscriber is required and must reference a key in the services map" $key) -}}
      {{- end -}}
      {{- if not (hasKey $.Values.services $trigger.subscriber) -}}
        {{- fail (printf "kafka.triggers.%s.subscriber references '%s' which does not exist in the services map" $key $trigger.subscriber) -}}
      {{- end -}}
      {{- if eq (index $.Values.services $trigger.subscriber).workload.type "Deployment" -}}
        {{- fail (printf "kafka.triggers.%s.subscriber references '%s' which uses workload.type: Deployment — a plain Kubernetes Service is not a Knative-addressable subscriber; point the subscriber at a Knative service" $key $trigger.subscriber) -}}
      {{- end -}}
      {{- if and $trigger.dlq $trigger.dlq.enabled -}}
        {{- if not (kindIs "map" $trigger.dlq.scaling) -}}
          {{- fail (printf "kafka.triggers.%s.dlq.scaling must be a map (got %v)" $key $trigger.dlq.scaling) -}}
        {{- end -}}
        {{- include "ksvc.validate.requireInteger" (dict "value" $trigger.dlq.scaling.minScale "path" (printf "kafka.triggers.%s.dlq.scaling.minScale" $key)) -}}
        {{- $dlqMinScale := int $trigger.dlq.scaling.minScale -}}
        {{- include "ksvc.validate.requireInteger" (dict "value" $trigger.dlq.scaling.maxScale "path" (printf "kafka.triggers.%s.dlq.scaling.maxScale" $key)) -}}
        {{- $dlqMaxScale := int $trigger.dlq.scaling.maxScale -}}
        {{- if lt $dlqMinScale 0 -}}
          {{- fail (printf "kafka.triggers.%s.dlq.scaling.minScale must be >= 0 (got %d)" $key $dlqMinScale) -}}
        {{- end -}}
        {{- if lt $dlqMaxScale 1 -}}
          {{- fail (printf "kafka.triggers.%s.dlq.scaling.maxScale must be >= 1 (got %d)" $key $dlqMaxScale) -}}
        {{- end -}}
        {{- if gt $dlqMinScale $dlqMaxScale -}}
          {{- fail (printf "kafka.triggers.%s.dlq.scaling: minScale (%d) must be <= maxScale (%d)" $key $dlqMinScale $dlqMaxScale) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* pingsource validation: sink, schedule/timezone, ceOverrides, and map key */}}
  {{- if .Values.pingsources -}}
    {{- range $key, $source := .Values.pingsources -}}
      {{- if not $source.sink -}}
        {{- fail (printf "pingsources.%s.sink is required and must reference a key in the services map" $key) -}}
      {{- end -}}
      {{- if not (hasKey $.Values.services $source.sink) -}}
        {{- fail (printf "pingsources.%s.sink references '%s' which does not exist in the services map" $key $source.sink) -}}
      {{- end -}}
      {{/* a Deployment-backed service exposes no Knative addressable, so it cannot be a PingSource sink */}}
      {{- if eq (index $.Values.services $source.sink).workload.type "Deployment" -}}
        {{- fail (printf "pingsources.%s.sink references '%s' which uses workload.type: Deployment — a plain Kubernetes Service is not a Knative-addressable sink; point the sink at a Knative service" $key $source.sink) -}}
      {{- end -}}
      {{- if not $source.schedule -}}
        {{- fail (printf "pingsources.%s.schedule is required" $key) -}}
      {{- end -}}
      {{- if not $source.timezone -}}
        {{- fail (printf "pingsources.%s.timezone is required" $key) -}}
      {{- end -}}
      {{- if and $source.ceOverrides (kindIs "map" $source.ceOverrides) (hasKey $source.ceOverrides "extensions") -}}
        {{- if not (kindIs "map" $source.ceOverrides.extensions) -}}
          {{- fail (printf "pingsources.%s.ceOverrides.extensions must be a map when set" $key) -}}
        {{- end -}}
        {{- if hasKey $source.ceOverrides.extensions "type" -}}
          {{- fail (printf "pingsources.%s.ceOverrides.extensions.type cannot be overridden (PingSource fixes the event type at dev.knative.sources.ping)" $key) -}}
        {{- end -}}
      {{- end -}}
      {{- if or (gt (len $key) 63) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $key)) -}}
        {{- fail (printf "pingsources.%s must be a DNS-1123 label" $key) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}

  {{/* cert-manager issuer validation: an enabled certManager block must resolve to a non-empty issuer name (locally or via global.certManager.issuerRef.name) */}}
  {{- $globalIssuerName := "" }}
  {{- if and .Values.global .Values.global.certManager -}}
    {{- $globalIssuerName = .Values.global.certManager.issuerRef.name | default "" -}}
  {{- end -}}
  {{- if and .Values.postgres.enabled .Values.postgres.certManager .Values.postgres.certManager.enabled -}}
    {{- $issuerName := .Values.postgres.certManager.issuerRef.name | default $globalIssuerName | toString | trim -}}
    {{- if not $issuerName -}}
      {{- fail "postgres.certManager: issuerRef.name must be set (locally or via global.certManager.issuerRef.name) when certManager is enabled — an empty issuerRef produces an invalid Certificate" -}}
    {{- end -}}
  {{- end -}}
  {{- if and .Values.dragonfly.enabled .Values.dragonfly.tls .Values.dragonfly.tls.certManager .Values.dragonfly.tls.certManager.enabled -}}
    {{- $issuerName := .Values.dragonfly.tls.certManager.issuerRef.name | default $globalIssuerName | toString | trim -}}
    {{- if not $issuerName -}}
      {{- fail "dragonfly.tls.certManager: issuerRef.name must be set (locally or via global.certManager.issuerRef.name) when certManager is enabled — an empty issuerRef produces an invalid Certificate" -}}
    {{- end -}}
  {{- end -}}

  {{/* dragonfly replica and PDB validation */}}
  {{- if .Values.dragonfly.enabled -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" .Values.dragonfly.replicas "path" "dragonfly.replicas") -}}
    {{- $dfReplicas := int .Values.dragonfly.replicas -}}
    {{- if or (lt $dfReplicas 1) (gt $dfReplicas 16) -}}
      {{- fail (printf "dragonfly.replicas must be >= 1 and <= 16 (got %d)" $dfReplicas) -}}
    {{- end -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" .Values.dragonfly.pdb.minAvailable "path" "dragonfly.pdb.minAvailable") -}}
    {{- $dfPdbMinAvailable := int .Values.dragonfly.pdb.minAvailable -}}
    {{- include "ksvc.validate.requireInteger" (dict "value" .Values.dragonfly.pdb.maxUnavailable "path" "dragonfly.pdb.maxUnavailable") -}}
    {{- $dfPdbMaxUnavailable := int .Values.dragonfly.pdb.maxUnavailable -}}
    {{- if and (ne $dfPdbMinAvailable 0) (ne $dfPdbMaxUnavailable 0) -}}
      {{- fail "dragonfly.pdb: minAvailable and maxUnavailable are mutually exclusive — set one of them to 0" -}}
    {{- end -}}
    {{- if and (ne $dfPdbMinAvailable 0) (gt $dfPdbMinAvailable $dfReplicas) -}}
      {{- fail (printf "dragonfly.pdb.minAvailable (%d) must be <= dragonfly.replicas (%d)" $dfPdbMinAvailable $dfReplicas) -}}
    {{- end -}}
  {{- end -}}

  {{/* dragonfly snapshot bucketRef validation (defensive read) */}}
  {{- $dfBucketRef := .Values.dragonfly.snapshot.bucketRef | default "" -}}
  {{- if $dfBucketRef -}}
    {{- if or (not .Values.dragonfly.enabled) (not .Values.dragonfly.snapshot.enabled) -}}
      {{- fail "dragonfly.snapshot.bucketRef requires dragonfly.enabled and dragonfly.snapshot.enabled" -}}
    {{- end -}}
    {{- if not (hasKey .Values.objectBuckets $dfBucketRef) -}}
      {{- fail (printf "dragonfly.snapshot.bucketRef references '%s' which does not exist in objectBuckets" $dfBucketRef) -}}
    {{- end -}}
    {{- if .Values.dragonfly.snapshot.existingPersistentVolumeClaimName -}}
      {{- fail "dragonfly.snapshot: bucketRef and existingPersistentVolumeClaimName are mutually exclusive" -}}
    {{- end -}}
    {{- if not (index .Values.objectBuckets $dfBucketRef).endpointURL -}}
      {{- fail "dragonfly.snapshot.bucketRef requires an endpointURL on the referenced bucket" -}}
    {{- end -}}
  {{- end -}}
{{- end }}

{{/*
ksvc.validate.requireInteger — Reject non-integer numeric values before they are
truncated by `int` (which would turn 1.5 into 1 and let invalid values through).
Accepts integer kinds and whole floats (e.g. 10.0); rejects fractional floats,
non-numeric strings, and non-numeric kinds. Negative integers are allowed here so
that the existing range checks (>= 0 / >= 1) keep producing their original messages.
*/}}
{{- define "ksvc.validate.requireInteger" -}}
{{- $v := .value -}}
{{- if kindIs "string" $v -}}
  {{- if not (regexMatch "^-?[0-9]+$" $v) -}}
    {{- fail (printf "%s must be an integer (got %s)" .path $v) -}}
  {{- end -}}
{{- else if kindIs "float64" $v -}}
  {{- if ne $v (floor $v) -}}
    {{- fail (printf "%s must be an integer (got %v)" .path $v) -}}
  {{- end -}}
{{- else if or (kindIs "bool" $v) (kindIs "slice" $v) (kindIs "map" $v) (kindIs "invalid" $v) -}}
  {{- fail (printf "%s must be an integer (got %v)" .path $v) -}}
{{- end -}}
{{- end }}
