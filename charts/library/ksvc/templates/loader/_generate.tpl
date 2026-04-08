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
  {{/* Knative Service (always rendered)                            */}}
  {{/* ============================================================ */}}
  {{- include "ksvc.class.knativeService" . | nindent 0 }}

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
  {{- end }}

  {{/* ============================================================ */}}
  {{/* Kafka Event Source                                           */}}
  {{/* ============================================================ */}}
  {{- if and .Values.kafka .Values.kafka.enabled }}
---
  {{- include "ksvc.class.kafkaSource" . | nindent 0 }}
    {{- if and .Values.kafka.dlq .Values.kafka.dlq.enabled }}
---
  {{- include "ksvc.class.kafkaDlq" . | nindent 0 }}
    {{- end }}
  {{- end }}

  {{/* ============================================================ */}}
  {{/* Flagger Canary Release                                      */}}
  {{/* ============================================================ */}}
  {{- if and .Values.flagger .Values.flagger.enabled }}
---
  {{- include "ksvc.class.flaggerCanary" . | nindent 0 }}
  {{- end }}

{{- end }}

{{/*
ksvc.loader.applyDefaults — Deep-merge library defaults into consumer values.
This compensates for Helm not merging library chart values.yaml automatically.
Uses mustMergeOverwrite: consumer values take precedence over defaults.
*/}}
{{- define "ksvc.loader.applyDefaults" -}}
  {{/* --- knativeService defaults --- */}}
  {{- $svcDefaults := dict
    "image" (dict "repository" "" "tag" "latest" "pullPolicy" "IfNotPresent" "fluxImagePolicy" "")
    "scaling" (dict "minScale" 1 "maxScale" 10 "target" 100 "containerConcurrency" 100 "timeoutSeconds" 300 "class" "")
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
  {{- $svc := .Values.knativeService | default dict -}}
  {{- $_ := set .Values "knativeService" (mustMergeOverwrite $svcDefaults $svc) -}}

  {{/* --- postgres defaults --- */}}
  {{- $pgDefaults := dict
    "enabled" false
    "version" "16"
    "instances" 3
    "parameters" (dict "ssl" "on" "ssl_min_protocol_version" "TLSv1.3" "ssl_max_protocol_version" "TLSv1.3" "shared_buffers" "2Gi" "max_connections" "300" "synchronous_commit" "remote_apply" "synchronous_standby_names" "ANY 1 (*)" "archive_timeout" "5min" "wal_compression" "on")
    "sharedPreloadLibraries" (list "pg_stat_statements")
    "postInitSQL" (list "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" "ALTER SYSTEM SET log_statement = 'all';" "ALTER SYSTEM SET log_min_duration_statement = '1000';")
    "resources" (dict "requests" (dict "cpu" "1" "memory" "2Gi") "limits" (dict "cpu" "2" "memory" "4Gi"))
    "storage" (dict "size" "200Gi" "storageClassName" "standard")
    "pooler" (dict "enabled" true "instances" 3 "type" "rw" "poolMode" "transaction"
      "parameters" (dict "max_client_conn" "300" "default_pool_size" "25" "reserve_pool_size" "5" "reserve_pool_timeout" "5" "max_db_connections" "100" "server_lifetime" "3600" "server_idle_timeout" "600" "log_connections" "1" "log_disconnections" "1" "log_pooler_errors" "1")
      "resources" (dict "requests" (dict "cpu" "100m" "memory" "128Mi") "limits" (dict "cpu" "500m" "memory" "256Mi"))
    )
    "backup" (dict "enabled" true "schedule" "0 2 * * *" "target" "prefer-standby" "retentionPolicy" "30d"
      "objectStore" (dict "destinationPath" "" "endpointURL" ""
        "s3Credentials" (dict "secretName" "postgres-backup-storage" "accessKeyIdKey" "ACCESS_KEY_ID" "secretAccessKeyKey" "ACCESS_SECRET_KEY")
        "data" (dict "compression" "zstd" "jobs" 2)
        "wal" (dict "compression" "gzip" "maxParallel" 4)
      )
    )
    "monitoring" (dict "enabled" true "alerts" (dict "replicationLagWarning" 10 "replicationLagCritical" 60 "highConnectionCount" 50))
  -}}
  {{- $pg := .Values.postgres | default dict -}}
  {{- $_ := set .Values "postgres" (mustMergeOverwrite $pgDefaults $pg) -}}

  {{/* --- kafka defaults --- */}}
  {{- $kafkaDefaults := dict
    "enabled" false
    "source" (dict "topic" "events" "consumerGroup" "" "bootstrapServers" (list "kafka.kafka.svc.cluster.local:9092") "consumers" 3 "initialOffset" "latest")
    "delivery" (dict "retry" 5 "backoffPolicy" "exponential" "backoffDelay" "PT1S")
    "dlq" (dict "enabled" true
      "image" (dict "repository" "gcr.io/knative-releases/knative.dev/eventing/cmd/event_display" "tag" "latest")
      "scaling" (dict "minScale" 0 "maxScale" 2)
      "resources" (dict "requests" (dict "cpu" "50m" "memory" "32Mi") "limits" (dict "cpu" "200m" "memory" "128Mi"))
    )
  -}}
  {{- $kafka := .Values.kafka | default dict -}}
  {{- $_ := set .Values "kafka" (mustMergeOverwrite $kafkaDefaults $kafka) -}}

  {{/* --- flagger defaults --- */}}
  {{- $flaggerDefaults := dict
    "enabled" false
    "analysis" (dict "interval" "1m" "threshold" 5 "maxWeight" 50 "stepWeight" 10 "progressDeadlineSeconds" 120)
    "metrics" (dict "successRateThreshold" 99 "latencyP99ThresholdMs" 500 "prometheusAddress" "http://prometheus.observability.svc.cluster.local:9090")
    "loadTest" (dict "enabled" true "webhookUrl" "http://k6-loadtester.flagger-system/launch-test" "vus" 10 "duration" "1m" "p95ThresholdMs" 500 "errorRateThreshold" 0.01 "script" "")
  -}}
  {{- $flagger := .Values.flagger | default dict -}}
  {{- $_ := set .Values "flagger" (mustMergeOverwrite $flaggerDefaults $flagger) -}}

  {{/* --- global defaults --- */}}
  {{- $globalDefaults := dict "nameOverride" "" "fullnameOverride" "" "labels" (dict) "annotations" (dict) -}}
  {{- $global := .Values.global | default dict -}}
  {{- $_ := set .Values "global" (mustMergeOverwrite $globalDefaults $global) -}}

{{- end }}
