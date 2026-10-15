{{/*
ksvc.loader.generate — Render all enabled resources.
Called from the consumer chart's templates/common.yaml.

Because this is a library chart, our values.yaml defaults are NOT automatically
merged. We must apply defaults explicitly before rendering.
*/}}
{{- define "ksvc.loader.generate" -}}

  {{/* ============================================================ */}}
  {{/* Apply defaults for values not provided by the consumer       */}}
  {{/* ============================================================ */}}
  {{- include "ksvc.loader.applyDefaults" . -}}

  {{/* Run validations */}}
  {{- include "ksvc.validate" . -}}

  {{/* ============================================================ */}}
  {{/* Knative Services (iterate the services map)                  */}}
  {{/* ============================================================ */}}
  {{- $isFirst := true -}}
  {{- range $key, $svc := .Values.services }}
    {{- if $isFirst -}}
      {{- $isFirst = false -}}
    {{- else }}
---
    {{- end }}
  {{- include "ksvc.class.knativeService" (dict "root" $ "key" $key "svc" $svc) | nindent 0 }}
    {{/* Flagger Canary (per-service opt-in) */}}
    {{- if and $svc.flagger $svc.flagger.enabled }}
---
  {{- include "ksvc.class.flaggerCanary" (dict "root" $ "key" $key "svc" $svc) | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* Object Buckets (one ObjectBucketClaim per entry)             */}}
  {{/* ============================================================ */}}
  {{- if .Values.objectBuckets }}
    {{- range $key, $bucket := .Values.objectBuckets }}
---
  {{- include "ksvc.class.objectBucketClaim" (dict "root" $ "key" $key "bucket" $bucket) | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* CloudNativePG PostgreSQL                                     */}}
  {{/* ============================================================ */}}
  {{- if and .Values.postgres .Values.postgres.enabled }}
---
  {{- include "ksvc.class.cnpgCluster" . | nindent 0 }}
    {{- if and .Values.postgres.pooler .Values.postgres.pooler.enabled }}
---
  {{- include "ksvc.class.cnpgPooler" . | nindent 0 }}
    {{- end }}
    {{- if and .Values.postgres.backup .Values.postgres.backup.enabled }}
---
  {{- include "ksvc.class.cnpgObjectStore" . | nindent 0 }}
---
  {{- include "ksvc.class.cnpgScheduledBackup" . | nindent 0 }}
    {{- end }}
    {{- if and .Values.postgres.monitoring .Values.postgres.monitoring.enabled }}
---
  {{- include "ksvc.class.cnpgPodMonitor" . | nindent 0 }}
---
  {{- include "ksvc.class.cnpgAlerts" . | nindent 0 }}
    {{- end }}
    {{- if and .Values.postgres.certManager .Values.postgres.certManager.enabled }}
---
  {{- include "ksvc.class.certManagerPostgres" . | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* Kafka Event Sources (iterate the kafka.sources map)          */}}
  {{/* ============================================================ */}}
  {{- if and .Values.kafka .Values.kafka.sources }}
    {{- range $key, $source := .Values.kafka.sources }}
---
  {{- include "ksvc.class.kafkaSource" (dict "root" $ "key" $key "source" $source) | nindent 0 }}
      {{- if and $source.dlq $source.dlq.enabled }}
---
  {{- include "ksvc.class.kafkaDlq" (dict "root" $ "key" $key "source" $source) | nindent 0 }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* DragonflyDB Cache Cluster                                   */}}
  {{/* ============================================================ */}}
  {{- if and .Values.dragonfly .Values.dragonfly.enabled }}
---
  {{- include "ksvc.class.dragonfly" . | nindent 0 }}
    {{- if and .Values.dragonfly.tls .Values.dragonfly.tls.certManager .Values.dragonfly.tls.certManager.enabled }}
---
  {{- include "ksvc.class.certManagerDragonfly" . | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* Kyverno Admission Policies (opt-in)                         */}}
  {{/* ============================================================ */}}
  {{- if and .Values.kyverno .Values.kyverno.enabled .Values.kyverno.scaling .Values.kyverno.scaling.enabled }}
---
{{- include "ksvc.class.kyvernoScaling" . | nindent 0 }}
{{- end }}

{{- end }}

{{/*
ksvc.loader.applyDefaults — Deep-merge library defaults into consumer values.
This compensates for Helm not merging library chart values.yaml automatically.
Uses mustMergeOverwrite: consumer values take precedence over defaults.
*/}}
{{- define "ksvc.loader.applyDefaults" -}}

  {{/* --- service defaults (applied to each entry in the services map) --- */}}
  {{- $svcDefaults := dict
    "image" (dict "repository" "" "tag" "latest" "digest" "" "pullPolicy" "IfNotPresent" "fluxImagePolicy" "" "imagePullSecrets" (list))
    "scaling" (dict "minScale" 1 "maxScale" 10 "target" 100 "containerConcurrency" 100 "timeoutSeconds" 300 "class" "" "metric" "")
    "resources" (dict "requests" (dict "cpu" "100m" "memory" "64Mi") "limits" (dict "cpu" "500m" "memory" "256Mi"))
    "port" 8080
    "probes" (dict
      "liveness" (dict "path" "/health/live" "port" 8080 "initialDelaySeconds" 3 "periodSeconds" 10 "timeoutSeconds" 2 "failureThreshold" 3)
      "readiness" (dict "path" "/health/ready" "port" 8080 "initialDelaySeconds" 5 "periodSeconds" 5 "timeoutSeconds" 3 "failureThreshold" 2)
    )
    "env" (list)
    "envFrom" (list)
    "securityContext" (dict
      "runAsNonRoot" true
      "runAsUser" 10001
      "readOnlyRootFilesystem" true
      "allowPrivilegeEscalation" false
      "seccompProfile" (dict "type" "RuntimeDefault")
      "capabilities" (dict "drop" (list "ALL"))
    )
    "volumeMounts" (list)
    "volumes" (list)
    "podAnnotations" (dict "prometheus.io/scrape" "true" "prometheus.io/port" "8080" "prometheus.io/path" "/metrics")
    "annotations" (dict "prometheus.io/scrape" "true" "prometheus.io/port" "8080" "prometheus.io/path" "/metrics")
    "labels" (dict)
  -}}

  {{- $flaggerDefaults := dict
    "enabled" false
    "analysis" (dict "interval" "1m" "threshold" 5 "maxWeight" 50 "stepWeight" 10 "progressDeadlineSeconds" 120)
    "metrics" (dict "successRateThreshold" 99 "latencyP99ThresholdMs" 500 "prometheusAddress" "http://prometheus.observability.svc.cluster.local:9090")
    "loadTest" (dict "enabled" true "webhookUrl" "http://k6-loadtester.flagger-system/launch-test" "vus" 10 "duration" "1m" "p95ThresholdMs" 500 "errorRateThreshold" 0.01 "script" "")
  -}}

  {{- $services := .Values.services | default dict -}}
  {{- range $key, $svc := $services }}
    {{- $merged := mustMergeOverwrite (deepCopy $svcDefaults) $svc -}}
    {{/* Merge flagger defaults into the service's flagger config */}}
    {{- $svcFlagger := $merged.flagger | default dict -}}
    {{- $_ := set $merged "flagger" (mustMergeOverwrite (deepCopy $flaggerDefaults) $svcFlagger) -}}
    {{- $_ := set $services $key $merged -}}
  {{- end }}
  {{- $_ := set .Values "services" $services -}}

  {{/* --- kafka source defaults (applied to each entry in kafka.sources map) --- */}}
  {{- $kafkaSourceDefaults := dict
    "topic" "events"
    "consumerGroup" ""
    "bootstrapServers" (list "kafka.kafka.svc.cluster.local:9092")
    "consumers" 3
    "initialOffset" "latest"
    "sink" ""
    "delivery" (dict "retry" 5 "backoffPolicy" "exponential" "backoffDelay" "PT1S")
    "dlq" (dict "enabled" true
      "image" (dict "repository" "gcr.io/knative-releases/knative.dev/eventing/cmd/event_display" "tag" "v1.17.0")
      "imagePullSecrets" (list)
      "scaling" (dict "minScale" 0 "maxScale" 2)
      "resources" (dict "requests" (dict "cpu" "50m" "memory" "32Mi") "limits" (dict "cpu" "200m" "memory" "128Mi"))
      "securityContext" (dict
        "runAsNonRoot" true
        "runAsUser" 10001
        "readOnlyRootFilesystem" true
        "allowPrivilegeEscalation" false
        "seccompProfile" (dict "type" "RuntimeDefault")
        "capabilities" (dict "drop" (list "ALL"))
      )
    )
  -}}

  {{- $kafka := .Values.kafka | default dict -}}
  {{- if or (not (hasKey $kafka "sources")) (not $kafka.sources) -}}
    {{- $_ := set $kafka "sources" dict -}}
  {{- end -}}
  {{- range $key, $source := $kafka.sources }}
    {{- $merged := mustMergeOverwrite (deepCopy $kafkaSourceDefaults) $source -}}
    {{- $_ := set $kafka.sources $key $merged -}}
  {{- end }}
  {{- $_ := set .Values "kafka" $kafka -}}

  {{/* --- object bucket defaults (applied to each entry in the objectBuckets map) --- */}}
  {{- $bucketDefaults := dict "bucketName" "" "endpointURL" "" "region" "" -}}
  {{- $buckets := .Values.objectBuckets | default dict -}}
  {{- range $key, $bucket := $buckets }}
    {{- $merged := mustMergeOverwrite (deepCopy $bucketDefaults) $bucket -}}
    {{- $_ := set $merged "bucketName" (default (include "ksvc.objectBucketName" (dict "root" $ "key" $key)) $merged.bucketName) -}}
    {{- $_ := set $buckets $key $merged -}}
  {{- end -}}
  {{- $_ := set .Values "objectBuckets" $buckets -}}

  {{/* --- postgres defaults --- */}}
  {{/* Capture RAW consumer objectStore values before the merge so bucketRef
       derivation can tell "consumer set it" apart from "we defaulted it".
       NOTE: sprig `dig` type-asserts its dict to map[string]interface{} and
       rejects chartutil.Values, so walk the nested maps explicitly instead. */}}
  {{- $pgRaw := .Values.postgres | default dict -}}
  {{- $pgBackupRaw := $pgRaw.backup | default dict -}}
  {{- $pgStoreRaw := $pgBackupRaw.objectStore | default dict -}}
  {{- $pgCredsRaw := $pgStoreRaw.s3Credentials | default dict -}}
  {{- $rawPgBucketRef := $pgStoreRaw.bucketRef | default "" -}}
  {{- $rawPgDestPath := $pgStoreRaw.destinationPath | default "" -}}
  {{- $rawPgEndpoint := $pgStoreRaw.endpointURL | default "" -}}
  {{- $rawPgCredSecret := $pgCredsRaw.secretName | default "" -}}
  {{- $rawPgCredAccess := $pgCredsRaw.accessKeyIdKey | default "" -}}
  {{- $rawPgCredSecretKey := $pgCredsRaw.secretAccessKeyKey | default "" -}}
  {{- $pgCredsProvided := or $rawPgCredSecret $rawPgCredAccess $rawPgCredSecretKey -}}
  {{- $pgDefaults := dict
    "enabled" false
    "version" "16"
    "instances" 3
    "imageCatalog" (dict "name" "postgresql")
    "imagePullSecrets" (list)
    "parameters" (dict "ssl" "on" "ssl_min_protocol_version" "TLSv1.3" "ssl_max_protocol_version" "TLSv1.3" "shared_buffers" "2Gi" "max_connections" "300" "synchronous_commit" "remote_apply" "synchronous_standby_names" "ANY 1 (*)" "archive_timeout" "5min" "wal_compression" "on")
    "sharedPreloadLibraries" (list "pg_stat_statements")
    "postInitSQL" (list "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;")
    "resources" (dict "requests" (dict "cpu" "1" "memory" "2Gi") "limits" (dict "cpu" "2" "memory" "4Gi"))
    "storage" (dict "size" "200Gi" "storageClassName" "standard")
    "pooler" (dict "enabled" true "instances" 3 "type" "rw" "poolMode" "transaction"
      "parameters" (dict "max_client_conn" "300" "default_pool_size" "25" "reserve_pool_size" "5" "reserve_pool_timeout" "5" "max_db_connections" "100" "server_lifetime" "3600" "server_idle_timeout" "600" "log_connections" "1" "log_disconnections" "1" "log_pooler_errors" "1")
      "resources" (dict "requests" (dict "cpu" "100m" "memory" "128Mi") "limits" (dict "cpu" "500m" "memory" "256Mi"))
    )
    "backup" (dict "enabled" true "schedule" "0 2 * * *" "target" "prefer-standby" "retentionPolicy" "30d"
      "objectStore" (dict "bucketRef" "" "destinationPath" "" "endpointURL" ""
        "s3Credentials" (dict "secretName" "postgres-backup-storage" "accessKeyIdKey" "ACCESS_KEY_ID" "secretAccessKeyKey" "ACCESS_SECRET_KEY")
        "data" (dict "compression" "gzip" "jobs" 2)
        "wal" (dict "compression" "gzip" "maxParallel" 4)
      )
    )
    "monitoring" (dict "enabled" true "alerts" (dict "replicationLagWarning" 10 "replicationLagCritical" 60 "highConnectionCount" 50))
    "certManager" (dict "enabled" false "issuerRef" (dict "name" "" "kind" "" "group" ""))
  -}}
  {{- $pg := .Values.postgres | default dict -}}
  {{- $_ := set .Values "postgres" (mustMergeOverwrite $pgDefaults $pg) -}}

  {{/* --- postgres bucketRef wiring (objectBuckets entries are defaulted above) --- */}}
  {{- if and $rawPgBucketRef (hasKey (.Values.objectBuckets | default dict) $rawPgBucketRef) -}}
    {{- $entry := index .Values.objectBuckets $rawPgBucketRef -}}
    {{- $claimName := include "ksvc.objectBucketName" (dict "root" $ "key" $rawPgBucketRef) -}}
    {{- $store := .Values.postgres.backup.objectStore -}}
    {{- if not $rawPgDestPath -}}
      {{- $_ := set $store "destinationPath" (printf "s3://%s/" $entry.bucketName) -}}
    {{- end -}}
    {{- if not $rawPgEndpoint -}}
      {{- $_ := set $store "endpointURL" $entry.endpointURL -}}
    {{- end -}}
    {{- if not $pgCredsProvided -}}
      {{- $_ := set $store.s3Credentials "secretName" $claimName -}}
      {{- $_ := set $store.s3Credentials "accessKeyIdKey" "AWS_ACCESS_KEY_ID" -}}
      {{- $_ := set $store.s3Credentials "secretAccessKeyKey" "AWS_SECRET_ACCESS_KEY" -}}
    {{- end -}}
  {{- end -}}

  {{/* --- dragonfly defaults --- */}}
  {{- $dfDefaults := dict
    "enabled" false
    "replicas" 3
    "image" "docker.dragonflydb.io/dragonflydb/dragonfly"
    "imageTag" "v1.21.2"
    "args" (list)
    "env" (list)
    "resources" (dict "requests" (dict "cpu" "500m" "memory" "512Mi") "limits" (dict "cpu" "1" "memory" "1Gi"))
    "authentication" (dict "passwordFromSecret" (dict "name" "" "key" "password") "clientCaCertSecret" (dict "name" "" "key" "ca.crt"))
    "tls" (dict "secretName" "" "certManager" (dict "enabled" false "issuerRef" (dict "name" "" "kind" "" "group" "") "duration" "2160h" "renewBefore" "360h"))
    "snapshot" (dict "enabled" false "cron" "0 */6 * * *" "enableOnMasterOnly" true
      "storage" (dict "size" "10Gi" "storageClassName" "")
    )
    "serviceSpec" (dict "type" "ClusterIP" "name" "" "nodePort" 0 "annotations" (dict) "labels" (dict))
    "pdb" (dict "minAvailable" 2 "maxUnavailable" 0)
    "affinity" (dict)
    "tolerations" (list)
    "topologySpreadConstraints" (list)
    "nodeSelector" (dict)
    "podSecurityContext" (dict)
    "containerSecurityContext" (dict)
    "serviceAccountName" ""
    "priorityClassName" ""
  -}}
  {{- $df := .Values.dragonfly | default dict -}}
  {{- $_ := set .Values "dragonfly" (mustMergeOverwrite $dfDefaults $df) -}}

  {{/* --- kyverno defaults --- */}}
  {{- $kyvernoDefaults := dict
    "enabled" false
    "scaling" (dict "enabled" false "apiVersion" "policies.kyverno.io/v1beta1" "validationActions" (list "Deny"))
  -}}
  {{- $kyverno := .Values.kyverno | default dict -}}
  {{- $_ := set .Values "kyverno" (mustMergeOverwrite $kyvernoDefaults $kyverno) -}}

  {{/* --- global defaults --- */}}
  {{- $globalDefaults := dict
    "nameOverride" ""
    "fullnameOverride" ""
    "labels" (dict)
    "annotations" (dict)
    "imagePullSecrets" (list)
    "certManager" (dict "issuerRef" (dict "name" "" "kind" "ClusterIssuer" "group" "cert-manager.io"))
  -}}
  {{- $global := .Values.global | default dict -}}
  {{- $_ := set .Values "global" (mustMergeOverwrite $globalDefaults $global) -}}

{{- end }}
