{{/*
ksvc.loader.defaults — The single copy of the loader's built-in defaults.

`ksvc.loader.effectiveValues` merges these dicts under the consumer's values
(consumer values win) to compute the effective values it renders from, and
`hack/check-defaults-parity.py` compares them against `values.yaml` through
`ksvc.loader.defaultsDump` — values.yaml and this file must stay in sync.

Callers pass an out-dict; every raw default dict is written into it under a
stable key:

  svc          -> defaults for each `services.<key>` entry
  flagger      -> defaults for each `services.<key>.flagger` block
  kafkaSource  -> defaults for each `kafka.sources.<key>` entry
  bucket       -> defaults for each `objectBuckets.<key>` entry
  postgres     -> `postgres` defaults
  dragonfly    -> `dragonfly` defaults
  kyverno      -> `kyverno` defaults
  global       -> `global` defaults
*/}}
{{- define "ksvc.loader.defaults" -}}
{{- $out := .out -}}
  {{- $_ := set $out "svc" (dict
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
    "podAnnotations" (dict "prometheus.io/scrape" "true" "prometheus.io/path" "/metrics")
    "annotations" (dict "prometheus.io/scrape" "true" "prometheus.io/path" "/metrics")
    "labels" (dict)
    "affinity" (dict)
    "tolerations" (list)
    "topologySpreadConstraints" (list)
    "nodeSelector" (dict)
    "serviceAccountName" ""
  ) -}}

  {{- $_ := set $out "flagger" (dict
    "enabled" false
    "preWebhookTimeout" "1m"
    "postWebhookTimeout" "5m"
    "analysis" (dict "interval" "1m" "threshold" 5 "maxWeight" 50 "stepWeight" 10 "progressDeadlineSeconds" 120)
    "metrics" (dict "successRateThreshold" 99 "latencyP99ThresholdMs" 500)
    "loadTest" (dict "enabled" true "webhookUrl" "http://k6-loadtester.flagger-system/launch-test" "vus" 10 "duration" "1m" "p95ThresholdMs" 500 "errorRateThreshold" 0.01 "script" "")
  ) -}}

  {{- $_ := set $out "kafkaSource" (dict
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
  ) -}}

  {{- $_ := set $out "bucket" (dict "bucketName" "" "endpointURL" "" "region" "") -}}

  {{- $_ := set $out "postgres" (dict
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
      "securityContext" (dict
        "runAsNonRoot" true
        "allowPrivilegeEscalation" false
        "seccompProfile" (dict "type" "RuntimeDefault")
        "capabilities" (dict "drop" (list "ALL"))
      )
    )
    "networkPolicy" (dict "enabled" false "extraIngress" (list))
    "backup" (dict "enabled" true "schedule" "0 2 * * *" "target" "prefer-standby" "retentionPolicy" "30d"
      "objectStore" (dict "bucketRef" "" "destinationPath" "" "endpointURL" ""
        "s3Credentials" (dict "secretName" "postgres-backup-storage" "accessKeyIdKey" "ACCESS_KEY_ID" "secretAccessKeyKey" "ACCESS_SECRET_KEY")
        "data" (dict "compression" "gzip" "jobs" 2)
        "wal" (dict "compression" "gzip" "maxParallel" 4)
      )
    )
    "monitoring" (dict "enabled" true "alerts" (dict "replicationLagWarning" 10 "replicationLagCritical" 60 "highConnectionCount" 50))
    "certManager" (dict "enabled" false "issuerRef" (dict "name" "" "kind" "" "group" ""))
  ) -}}

  {{- $_ := set $out "dragonfly" (dict
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
    "networkPolicy" (dict "enabled" false "extraIngress" (list))
    "affinity" (dict)
    "tolerations" (list)
    "topologySpreadConstraints" (list)
    "nodeSelector" (dict)
    "podSecurityContext" (dict
      "fsGroup" 999
      "seccompProfile" (dict "type" "RuntimeDefault")
    )
    "containerSecurityContext" (dict
      "runAsNonRoot" true
      "allowPrivilegeEscalation" false
      "seccompProfile" (dict "type" "RuntimeDefault")
      "capabilities" (dict "drop" (list "ALL"))
    )
    "serviceAccountName" ""
    "priorityClassName" ""
  ) -}}

  {{- $_ := set $out "kyverno" (dict
    "enabled" false
    "scaling" (dict "enabled" false "apiVersion" "policies.kyverno.io/v1beta1" "validationActions" (list "Deny"))
  ) -}}

  {{- $_ := set $out "global" (dict
    "nameOverride" ""
    "fullnameOverride" ""
    "labels" (dict)
    "annotations" (dict)
    "imagePullSecrets" (list)
    "certManager" (dict "issuerRef" (dict "name" "" "kind" "ClusterIssuer" "group" "cert-manager.io"))
  ) -}}

{{- end }}

{{/*
ksvc.loader.defaultsDump — Render every raw default dict as YAML for the
defaults-parity check.

Gated on `.Values.__ksvcDumpDefaults`, which no release sets, so a normal
render emits nothing. To request the dump explicitly:

  helm template release <consumer-chart> \
    --set __ksvcDumpDefaults=true \
    --set services.api.image.repository=x/y

The test-chart probe (charts/library/ksvc/test-chart/templates/values-probe.yaml)
includes this define; `ksvc.loader.generate` never does.
*/}}
{{- define "ksvc.loader.defaultsDump" -}}
{{- if .Values.__ksvcDumpDefaults -}}
{{- $d := dict -}}
{{- include "ksvc.loader.defaults" (dict "out" $d) -}}
{{ dict "__ksvcDefaultsDump" (dict
  "svcDefaults" $d.svc
  "flaggerDefaults" $d.flagger
  "kafkaSourceDefaults" $d.kafkaSource
  "bucketDefaults" $d.bucket
  "pgDefaults" $d.postgres
  "dfDefaults" $d.dragonfly
  "globalDefaults" $d.global
  "kyvernoDefaults" $d.kyverno
) | toYaml }}
{{- end -}}
{{- end -}}
