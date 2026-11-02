# ksvc

Helm library chart for deploying **multiple Knative services** (or standard Deployments for long-running workloads such as websockets) with integrated CloudNativePG, Kafka event sources, DragonflyDB, and Flagger canary releases.

## Overview

This library chart provides a standardized way to deploy serverless applications on Kubernetes using Knative Serving. Consumers define one or more services via a `services:` map, and the library renders all required Kubernetes and Custom Resource manifests. A service can opt into a standard Kubernetes Deployment instead of Knative (see [Long-Running Services](#long-running-services-deployment-workload)).

Infrastructure resources (PostgreSQL, DragonflyDB) are shared globally across all services in the release, while Kafka event sources and Flagger canary configs are scoped per-source and per-service respectively.

## Architecture

```
Consumer Chart
  └── templates/common.yaml
        └── {{ include "ksvc.loader.generate" . }}
              ├── Validators (sink refs, required fields)
              ├── Per-service loop (services map)
              │     ├── Knative Service (default)
              │     │     └── Flagger Canary (opt-in)
              │     └── Deployment workload (workload.type: Deployment, opt-in)
              │           ├── apps/v1 Deployment
              │           ├── core/v1 Service
              │           └── PodDisruptionBudget (opt-in)
              ├── Kafka Broker (kafka.broker.enabled, opt-in)
              │     ├── Broker ConfigMap
              │     └── Broker
              ├── Per-source loop (kafka.sources map)
              │     ├── KafkaSource
              │     └── DLQ Knative Service (opt-in)
              ├── Per-trigger loop (kafka.triggers map)
              │     ├── Trigger
              │     └── Trigger DLQ Knative Service (opt-in)
              ├── Per-source loop (pingsources map)
              │     └── PingSource
              └── Global resources
                    ├── ObjectBucketClaim (per objectBuckets entry, opt-in)
                    ├── CNPG Cluster, Pooler, Backup, ObjectStore, PodMonitor, Alerts
                    └── Dragonfly
```

### Naming Conventions

| Resource | Name Pattern |
|----------|-------------|
| Knative Service | `<release>-<service-key>` (or `<release>-<nameOverride>` when set) |
| Flagger Canary | `<release>-<service-key>` (or `<release>-<nameOverride>` when set) |
| Deployment (Deployment mode) | `<release>-<service-key>` (or `<release>-<nameOverride>` when set) |
| core/v1 Service (Deployment mode) | `<release>-<service-key>` (shares the Deployment's name) |
| PodDisruptionBudget (Deployment mode, opt-in) | `<release>-<service-key>` |
| KafkaSource | `<release>-<source-key>-kafka-source` |
| DLQ Service | `<release>-<source-key>-dlq` |
| Broker ConfigMap | `<release>-kafka-broker-config` (when `kafka.broker.enabled: true`) |
| Broker | `<release>-kafka-broker` (when `kafka.broker.enabled: true`) |
| Trigger | `<release>-<trigger-key>-trigger` (per `kafka.triggers` entry) |
| Trigger DLQ Service | `<release>-<trigger-key>-trigger-dlq` (per trigger with `dlq.enabled: true`) |
| PingSource | `<release>-<source-key>-ping-source` (per `pingsources` entry) |
| CNPG Cluster | `<release>` (global) |
| Dragonfly | `<release>` (global) |
| ObjectBucketClaim | `<release>-<key>` (per `objectBuckets` entry) |

In Deployment mode the Deployment, the core/v1 Service, and any PodDisruptionBudget all share the `<release>-<service-key>` name. Sharing a name across kinds is legal in Kubernetes; the resources are linked by selectors, not by name.

Use `nameOverride: ""` on a service entry to produce just `<release>` with no suffix — useful for single-service deployments or kustomize compatibility.

ObjectBucketClaim names are sanitized the same way as the others: truncated to 63 chars, trailing `-` trimmed, and `_` replaced with `-`. The provisioner names the claim's Secret and ConfigMap after the claim, and the entry's default `bucketName` equals this claim name unless you set `objectBuckets.<key>.bucketName`.

## Quick Start

1.  Create a new Helm chart:
    ```bash
    helm create my-service
    rm -rf my-service/templates/*
    ```

2.  Add the dependency to `Chart.yaml`:
    ```yaml
    dependencies:
      - name: ksvc
        version: 0.10.0
        repository: oci://ghcr.io/enchantednatures/charts
    ```

3.  Create `my-service/templates/common.yaml`:
    ```yaml
    {{- include "ksvc.loader.generate" . }}
    ```

4.  Configure `values.yaml`:
    ```yaml
    services:
      api:
        image:
          repository: ghcr.io/my-org/my-api
          tag: v1.0.0
      worker:
        image:
          repository: ghcr.io/my-org/my-worker
          tag: v1.0.0
    ```

    This renders two Knative Services: `my-service-api` and `my-service-worker`.

## Resources Rendered

| Feature | Resources Rendered | Scope |
|---------|-------------------|-------|
| **Services** | Knative Service (per entry in `services`) | Per-service |
| **Long-running services (opt-in)** | apps/v1 Deployment + core/v1 Service + optional policy/v1 PodDisruptionBudget (per service with `workload.type: Deployment`) | Per-service |
| **Flagger** | Canary (per service with `flagger.enabled: true`) | Per-service |
| **Kafka** | KafkaSource (per entry in `kafka.sources`) | Per-source |
| **Kafka DLQ** | Knative Service (per source with `dlq.enabled: true`) | Per-source |
| **Kafka Broker (opt-in)** | ConfigMap + Broker (when `kafka.broker.enabled: true`) | Global |
| **Kafka Triggers (opt-in)** | Trigger + optional Knative Service DLQ (per entry in `kafka.triggers`) | Per-trigger |
| **PingSource** | PingSource (per entry in `pingsources`) | Per-source |
| **PostgreSQL** | Cluster, Pooler, ObjectStore, ScheduledBackup, PodMonitor, PrometheusRule | Global |
| **DragonflyDB** | Dragonfly | Global |
| **Object Buckets (opt-in)** | ObjectBucketClaim (per entry in `objectBuckets`) | Global |
| **Kyverno (opt-in)** | NamespacedValidatingPolicy (3x: Knative scaling, CNPG instances, Dragonfly replicas/PDB) | Namespace |

## Values Reference

> **Schema validation note:** Helm does **not** validate a library chart's `values.schema.json` against consumer values passed through the loader — the schema above `ksvc`'s own install only. Render-time checks enforced by `_validators.tpl` (required fields, cross-references, cert-manager issuers) are the true enforcement; CI validates example values against this schema. If a "required" check matters, also rely on the validator behavior.
>
> Scaling and replica/instance counts are also enforced at render time by `_validators.tpl`: service scaling (`minScale`, `maxScale`, `target`, `containerConcurrency`, `timeoutSeconds`), postgres instances (1–16), pooler instances (≥ 1), and Dragonfly replicas (1–16). The Dragonfly PDB rules are checked too: `minAvailable` and `maxUnavailable` are mutually exclusive (setting both non-zero now fails rendering) and `minAvailable` must be `<= replicas`.

The table below is generated from [`values.yaml`](values.yaml) by
[helm-docs](https://github.com/norwoodj/helm-docs) — do not edit it by hand,
run `make docs` instead.

`services`, `kafka.sources`, `pingsources`, and `objectBuckets` are keyed maps:
use any consumer-chosen key. The generated table uses the default example key
(`api`) for `services`. Because `kafka.sources`, `pingsources`, and
`objectBuckets` ship empty, their per-entry schemas are documented in the
sections following the table.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| dragonfly.affinity | object | `{}` | Pod affinity rules. |
| dragonfly.args | list | `[]` | Extra Dragonfly CLI arguments (e.g. `--cluster_mode=emulated`). |
| dragonfly.authentication.clientCaCertSecret.key | string | `"ca.crt"` | Key within the client CA Secret. |
| dragonfly.authentication.clientCaCertSecret.name | string | `""` | Secret containing the mTLS client CA certificate. |
| dragonfly.authentication.passwordFromSecret.key | string | `"password"` | Key within the password Secret. |
| dragonfly.authentication.passwordFromSecret.name | string | `""` | Secret containing the Dragonfly password. |
| dragonfly.containerSecurityContext | object | `{}` | Container-level security context. |
| dragonfly.enabled | bool | `false` | Enable the DragonflyDB cache cluster. |
| dragonfly.env | list | `[]` | Extra environment variables for the Dragonfly container. |
| dragonfly.image | string | `"docker.dragonflydb.io/dragonflydb/dragonfly"` | DragonflyDB container image repository. |
| dragonfly.imageTag | string | `"v1.21.2"` | DragonflyDB container image tag. |
| dragonfly.nodeSelector | object | `{}` | Node selector for the Dragonfly pods. |
| dragonfly.pdb.maxUnavailable | int | `0` | Maximum unavailable pods for the PodDisruptionBudget (mutually exclusive with `minAvailable`). |
| dragonfly.pdb.minAvailable | int | `2` | Minimum available pods for the PodDisruptionBudget (mutually exclusive with `maxUnavailable`). |
| dragonfly.podSecurityContext | object | `{}` | Pod-level security context. |
| dragonfly.priorityClassName | string | `""` | PriorityClass for the Dragonfly pods. |
| dragonfly.replicas | int | `3` | Total number of Dragonfly instances including the master (1–16). |
| dragonfly.resources | object | `500m`/`512Mi` requests, `1`/`1Gi` limits (see `values.yaml`) | Dragonfly container CPU/memory requests and limits. |
| dragonfly.serviceAccountName | string | `""` | ServiceAccount used by the Dragonfly pods. |
| dragonfly.serviceSpec.annotations | object | `{}` | Annotations for the Dragonfly Service. |
| dragonfly.serviceSpec.labels | object | `{}` | Labels for the Dragonfly Service. |
| dragonfly.serviceSpec.name | string | `""` | Override the generated Service name. |
| dragonfly.serviceSpec.nodePort | int | `0` | Node port (only used when `type` is `NodePort`). |
| dragonfly.serviceSpec.type | string | `"ClusterIP"` | Kubernetes Service type. |
| dragonfly.snapshot.cron | string | `"0 */6 * * *"` | Cron schedule for snapshots. |
| dragonfly.snapshot.dir | string | `""` | S3 backup path (`s3://bucket/path`); mutually exclusive with an existing PVC. Derived from `snapshot.bucketRef` when it is set. |
| dragonfly.snapshot.enableOnMasterOnly | bool | `true` | Take snapshots only on the master instance. |
| dragonfly.snapshot.enabled | bool | `false` | Enable snapshot persistence. |
| dragonfly.snapshot.existingPersistentVolumeClaimName | string | `""` | Use an existing PVC for snapshots (mutually exclusive with `dir` and `snapshot.bucketRef`). |
| dragonfly.snapshot.storage.size | string | `"10Gi"` | PVC size when neither `dir` nor an existing PVC is set. |
| dragonfly.snapshot.storage.storageClassName | string | `""` | StorageClass for the snapshot PVC. |
| dragonfly.tls.certManager.duration | string | `"2160h"` | Requested certificate lifetime. |
| dragonfly.tls.certManager.enabled | bool | `false` | Generate the Dragonfly TLS certificate via cert-manager. |
| dragonfly.tls.certManager.issuerRef.group | string | `""` | API group of the Dragonfly cert-manager issuer. |
| dragonfly.tls.certManager.issuerRef.kind | string | `""` | Kind of the Dragonfly cert-manager issuer. |
| dragonfly.tls.certManager.issuerRef.name | string | `""` | Override `global.certManager.issuerRef` for the Dragonfly certificate. |
| dragonfly.tls.certManager.renewBefore | string | `"360h"` | How long before expiry the certificate is renewed. |
| dragonfly.tls.secretName | string | `""` | Secret containing `tls.crt`/`tls.key`. Ignored when `tls.certManager.enabled` is true. |
| dragonfly.tolerations | list | `[]` | Pod tolerations. |
| dragonfly.topologySpreadConstraints | list | `[]` | Pod topology spread constraints. |
| global.annotations | object | `{}` | Annotations added to every rendered resource. |
| global.certManager.issuerRef.group | string | `"cert-manager.io"` | API group of the default cert-manager issuer. |
| global.certManager.issuerRef.kind | string | `"ClusterIssuer"` | Kind of the default cert-manager issuer (`Issuer` or `ClusterIssuer`). |
| global.certManager.issuerRef.name | string | `""` | Name of the default cert-manager Issuer/ClusterIssuer. |
| global.fullnameOverride | string | `""` | Override the fully qualified release name used for resource names (defaults to `<release>-<chart>`). |
| global.labels | object | `{}` | Labels added to every rendered resource. |
| global.nameOverride | string | `""` | Override the chart name (defaults to the chart name). |
| kafka.broker.annotations | object | `{}` | Annotations added to the Broker. |
| kafka.broker.config.authSecretName | string | `""` | Secret containing the broker's Kafka auth credentials. |
| kafka.broker.config.bootstrapServers | list | `["kafka.kafka.svc.cluster.local:9092"]` | Kafka bootstrap servers used by the broker. |
| kafka.broker.config.extra | object | `{}` | Extra ConfigMap entries for the broker. |
| kafka.broker.config.topicPartitions | int | `10` | Default partition count for broker-created topics. |
| kafka.broker.config.topicReplicationFactor | int | `3` | Default replication factor for broker-created topics. |
| kafka.broker.delivery.backoffDelay | string | `"PT1S"` | Backoff delay (ISO 8601). |
| kafka.broker.delivery.backoffPolicy | string | `"exponential"` | Backoff policy (`linear` or `exponential`). |
| kafka.broker.delivery.deadLetterSink.enabled | bool | `false` | Enable a dead-letter sink for the broker. |
| kafka.broker.delivery.deadLetterSink.ref.apiVersion | string | `"serving.knative.dev/v1"` | API version of the dead-letter sink reference. |
| kafka.broker.delivery.deadLetterSink.ref.kind | string | `"Service"` | Kind of the dead-letter sink reference. |
| kafka.broker.delivery.deadLetterSink.ref.name | string | `""` | Name of the dead-letter sink reference. |
| kafka.broker.delivery.deadLetterSink.uri | string | `""` | URI for the dead-letter sink (mutually exclusive with `ref`). |
| kafka.broker.delivery.retry | int | `5` | Delivery retry count. |
| kafka.broker.enabled | bool | `false` | Enable a Knative Eventing Broker backed by Kafka. |
| kafka.broker.externalTopic | string | `""` | Pre-existing Kafka topic used for the broker's internal state. |
| kafka.cluster.auth.type | string | `"none"` | Managed authentication type (`none` or `scram`). |
| kafka.cluster.auth.username | string | `""` | Managed username. Defaults to `<fullname>-kafka-user`. |
| kafka.cluster.enabled | bool | `false` | Enable a chart-managed Kafka cluster. |
| kafka.cluster.name | string | `""` | Cluster name. Defaults to `<fullname>-kafka`; max 47 characters. |
| kafka.cluster.provider | string | `"strimzi"` | Managed Kafka provider (`strimzi` or `redpanda`). |
| kafka.cluster.redpanda.extraClusterSpec | object | `{}` | Extra fields merged into the Redpanda `spec.clusterSpec`. |
| kafka.cluster.redpanda.sasl.secretRef | string | `""` | Superuser Secret for managed Redpanda SCRAM. |
| kafka.cluster.replicas | int | `3` | Broker/controller replicas (1-16). |
| kafka.cluster.resources.limits.cpu | string | `"2"` | CPU limit per broker. |
| kafka.cluster.resources.limits.memory | string | `"4Gi"` | Memory limit per broker. |
| kafka.cluster.resources.requests.cpu | string | `"500m"` | CPU request per broker. |
| kafka.cluster.resources.requests.memory | string | `"1Gi"` | Memory request per broker. |
| kafka.cluster.storage.size | string | `"20Gi"` | Persistent volume size per broker. |
| kafka.cluster.storage.storageClassName | string | `""` | StorageClass for broker volumes. |
| kafka.cluster.strimzi.extraSpec | object | `{}` | Extra fields merged into the Kafka `spec`. |
| kafka.cluster.strimzi.metadataVersion | string | `""` | Kafka metadata version (empty uses the operator default). |
| kafka.cluster.strimzi.nodePoolExtraSpec | object | `{}` | Extra fields merged into the KafkaNodePool `spec`. |
| kafka.cluster.strimzi.version | string | `""` | Strimzi Kafka version (empty uses the operator default). |
| kafka.cluster.tls.enabled | bool | `false` | Enable the internal TLS listener. |
| kafka.cluster.topics.create | bool | `true` | Create the source topics on the managed cluster. |
| kafka.cluster.topics.partitions | int | `3` | Partition count for created topics. |
| kafka.sources | object | `{}` | Map of KafkaSource entries, keyed by source name. Each key renders a KafkaSource named `<release>-<key>-kafka-source`; every entry's `sink` must reference a key in `services` (validated at render time). See the Kafka Event Sources section for the per-entry schema. |
| kafka.triggers | object | `{}` | Map of Kafka Trigger entries, keyed by trigger name. Each key renders a Trigger named `<release>-<key>-trigger`; every entry's `subscriber` must reference a key in `services` (validated at render time). Requires `kafka.broker.enabled: true`. See the Kafka Event Sources section for the per-entry schema. |
| kyverno.enabled | bool | `false` | Render the Kyverno admission policies. |
| kyverno.scaling.apiVersion | string | `"policies.kyverno.io/v1beta1"` | Policy `apiVersion` (`policies.kyverno.io/v1beta1` for Kyverno >= 1.16, `policies.kyverno.io/v1` for Kyverno >= 1.17). |
| kyverno.scaling.enabled | bool | `false` | Render the scaling/HA guardrail policies (Knative Service, CNPG instances, Dragonfly replicas/PDB). |
| kyverno.scaling.validationActions | list | `["Deny"]` | Enforcement actions (`Deny` and/or `Audit`). |
| objectBuckets | object | `{}` | Map of ObjectBucketClaim entries, keyed by an arbitrary bucket name. Each key renders an ObjectBucketClaim named `<release>-<key>`; see the Object Buckets section for the per-entry schema. |
| pingsources | object | `{}` | Map of PingSource entries, keyed by source name. Each key renders a PingSource named `<release>-<key>-ping-source`; every entry's `sink` must reference a key in `services` (validated at render time). Per-entry fields: `schedule`, `timezone`, `data`, `contentType`, `ceOverrides.extensions` (custom extensions only, never `type`), and the required `sink`. |
| postgres.backup.enabled | bool | `true` | Enable WAL archiving and scheduled backups. |
| postgres.backup.objectStore.data.compression | string | `"gzip"` | Compression algorithm for data backups (`snappy`, `gzip`, `bzip2` or `lz4`). |
| postgres.backup.objectStore.data.jobs | int | `2` | Number of parallel jobs for data backups. |
| postgres.backup.objectStore.destinationPath | string | `""` | Destination path for backups (e.g. `s3://bucket/path`). Derived from `bucketRef` when it is set. |
| postgres.backup.objectStore.endpointURL | string | `""` | S3 endpoint URL. Derived from the referenced bucket when `bucketRef` is set. |
| postgres.backup.objectStore.s3Credentials.accessKeyIdKey | string | `"ACCESS_KEY_ID"` | Key within the credentials Secret holding the access key id. |
| postgres.backup.objectStore.s3Credentials.secretAccessKeyKey | string | `"ACCESS_SECRET_KEY"` | Key within the credentials Secret holding the secret access key. |
| postgres.backup.objectStore.s3Credentials.secretName | string | `"postgres-backup-storage"` | Secret holding the S3 credentials. |
| postgres.backup.objectStore.wal.compression | string | `"gzip"` | Compression algorithm for WAL backups. |
| postgres.backup.objectStore.wal.maxParallel | int | `4` | Maximum number of parallel WAL uploads. |
| postgres.backup.retentionPolicy | string | `"30d"` | Backup retention period (e.g. `30d`). |
| postgres.backup.schedule | string | `"0 2 * * *"` | Cron schedule for backups. |
| postgres.backup.target | string | `"prefer-standby"` | Backup target (`prefer-standby` or `primary`). |
| postgres.certManager.enabled | bool | `false` | Generate PostgreSQL TLS certificates via cert-manager. |
| postgres.certManager.issuerRef.group | string | `""` | API group of the PostgreSQL cert-manager issuer. |
| postgres.certManager.issuerRef.kind | string | `""` | Kind of the PostgreSQL cert-manager issuer. |
| postgres.certManager.issuerRef.name | string | `""` | Override `global.certManager.issuerRef` for PostgreSQL certificates. |
| postgres.enabled | bool | `false` | Enable the CloudNativePG PostgreSQL cluster. |
| postgres.imageCatalog.name | string | `"postgresql"` | Name of the ClusterImageCatalog to pull the PostgreSQL image from. |
| postgres.instances | int | `3` | Number of PostgreSQL instances (1–16). |
| postgres.monitoring.alerts | object | see `values.yaml` | Alert thresholds for the Prometheus rules. |
| postgres.monitoring.enabled | bool | `true` | Enable the PodMonitor and Prometheus alert rules. |
| postgres.parameters | object | see `values.yaml` | PostgreSQL server configuration parameters (TLS 1.3, buffers, synchronous replication, ...). |
| postgres.pooler.enabled | bool | `true` | Enable the PgBouncer pooler. |
| postgres.pooler.instances | int | `3` | Number of pooler replicas (>= 1). |
| postgres.pooler.parameters | object | see `values.yaml` | PgBouncer configuration parameters. |
| postgres.pooler.poolMode | string | `"transaction"` | Pooler mode (`session` or `transaction`). |
| postgres.pooler.resources | object | see `values.yaml` | Pooler CPU/memory requests and limits. |
| postgres.pooler.type | string | `"rw"` | Pooler type (`rw` or `ro`). |
| postgres.postInitSQL | list | `["CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"]` | SQL statements run after cluster initialization. The default enables only `pg_stat_statements`. Statement logging is intentionally off because `log_statement = 'all'` writes every statement — including credentials and PII — to the Postgres logs, and `log_min_duration_statement` duplicates slow-query logging. It is opt-in: append the `ALTER SYSTEM` statements shown in the comment below to enable it. |
| postgres.resources | object | `1`/`2Gi` requests, `2`/`4Gi` limits (see `values.yaml`) | Cluster CPU/memory requests and limits. |
| postgres.sharedPreloadLibraries | list | `["pg_stat_statements"]` | Shared libraries preloaded by PostgreSQL. |
| postgres.storage.size | string | `"200Gi"` | Persistent volume size per instance. |
| postgres.storage.storageClassName | string | `"standard"` | StorageClass for the instance volumes. |
| postgres.version | string | `"16"` | PostgreSQL major version. |
| services.api.annotations | object | see `values.yaml` | Annotations added to the Knative Service (Prometheus scraping enabled by default). |
| services.api.env | list | `[]` | Environment variables for the container. |
| services.api.envFrom | list | `[]` | envFrom sources (Secrets/ConfigMaps) for the container. |
| services.api.flagger.analysis.interval | string | `"1m"` | Interval between canary analysis checks (Go duration, e.g. `1m`). |
| services.api.flagger.analysis.maxWeight | int | `50` | Maximum traffic weight (%) assigned to the canary. |
| services.api.flagger.analysis.progressDeadlineSeconds | int | `120` | Maximum seconds for the canary to make progress before rollback. |
| services.api.flagger.analysis.stepWeight | int | `10` | Traffic weight increment (%) per successful step. |
| services.api.flagger.analysis.threshold | int | `5` | Number of failed checks before the canary is rolled back. |
| services.api.flagger.enabled | bool | `false` | Enable a Flagger canary for this service. |
| services.api.flagger.loadTest.duration | string | `"1m"` | Duration of the k6 load test. |
| services.api.flagger.loadTest.enabled | bool | `true` | Enable k6 load testing during canary analysis. |
| services.api.flagger.loadTest.errorRateThreshold | float | `0.01` | Maximum error rate (fraction) tolerated by the load test. |
| services.api.flagger.loadTest.p95ThresholdMs | int | `500` | p95 latency threshold (ms) for the load test. |
| services.api.flagger.loadTest.script | string | `""` | Override the entire k6 load-test script. |
| services.api.flagger.loadTest.vus | int | `10` | Number of virtual users for the k6 load test. |
| services.api.flagger.loadTest.webhookUrl | string | `"http://k6-loadtester.flagger-system/launch-test"` | URL of the k6 webhook service that starts load tests. |
| services.api.flagger.metrics.latencyP99ThresholdMs | int | `500` | Maximum p99 latency (ms) allowed during analysis. |
| services.api.flagger.metrics.prometheusAddress | string | `"http://prometheus.observability.svc.cluster.local:9090"` | Prometheus server address used for metric checks. |
| services.api.flagger.metrics.successRateThreshold | int | `99` | Minimum success rate (%) required to promote the canary. |
| services.api.image.fluxImagePolicy | string | `""` | Flux image policy annotation. |
| services.api.image.imagePullSecrets | list | `[]` | List of imagePullSecrets attached to the pod spec (private registries). |
| services.api.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| services.api.image.repository | string | `""` | Container image repository. |
| services.api.image.tag | string | `"latest"` | Container image tag. |
| services.api.labels | object | `{}` | Additional labels for the Knative Service. |
| services.api.podAnnotations | object | see `values.yaml` | Annotations added to the pod template (Prometheus scraping enabled by default). |
| services.api.podDisruptionBudget.enabled | bool | `false` | Render a PodDisruptionBudget for this service. |
| services.api.podDisruptionBudget.maxUnavailable | int | `0` | Maximum unavailable pods (integer or percent string). |
| services.api.podDisruptionBudget.minAvailable | int | `0` | Minimum available pods (integer or percent string). |
| services.api.port | int | `8080` | Container port for the service. In Deployment mode it is also the Deployment container port and the core Service `targetPort`. |
| services.api.probes.liveness | object | see `values.yaml` | Liveness probe configuration (`httpGet`). |
| services.api.probes.readiness | object | see `values.yaml` | Readiness probe configuration (`httpGet`). |
| services.api.resources | object | `100m`/`64Mi` requests, `500m`/`256Mi` limits (see `values.yaml`) | Container CPU/memory requests and limits. |
| services.api.scaling.class | string | `""` | Autoscaler class (e.g. `kpa.autoscaling.knative.dev` or `hpa.autoscaling.knative.dev`). |
| services.api.scaling.containerConcurrency | int | `100` | Maximum concurrent requests per pod. |
| services.api.scaling.maxScale | int | `10` | Maximum number of replicas. |
| services.api.scaling.metric | string | `""` | Autoscaling metric: `concurrency`, `rps` (KPA), or `cpu`, `memory`, custom metric (HPA class only). Empty falls back to the Knative default (`concurrency`). |
| services.api.scaling.minScale | int | `1` | Minimum number of replicas. |
| services.api.scaling.target | int | `100` | Autoscaling target (requests in flight per pod for the KPA). |
| services.api.scaling.timeoutSeconds | int | `300` | Request timeout in seconds. |
| services.api.securityContext | object | see `values.yaml` | Container security context (non-root, read-only root fs, drops all capabilities). |
| services.api.service.annotations | object | `{}` | Annotations for the core Service, merged over `global.annotations`. |
| services.api.service.externalTrafficPolicy | string | `""` | External traffic policy: empty, `Cluster`, or `Local`. Only meaningful for `NodePort`/`LoadBalancer`; an empty value renders no field, and a non-empty value is rejected when `service.type` is `ClusterIP`. |
| services.api.service.labels | object | `{}` | Extra labels for the core Service. |
| services.api.service.port | int | `80` | Service port. The container `targetPort` always follows the service entry's `port` value above. |
| services.api.service.sessionAffinity | string | `"None"` | Session affinity: `None` or `ClientIP`. |
| services.api.service.sessionAffinityConfig.clientIP.timeoutSeconds | int | `10800` | ClientIP affinity timeout in seconds (rendered only when `sessionAffinity` is `ClientIP`). |
| services.api.service.type | string | `"ClusterIP"` | Service type: `ClusterIP`, `NodePort`, or `LoadBalancer`. |
| services.api.volumeMounts | list | `[]` | Additional volume mounts for the container. |
| services.api.volumes | list | `[]` | Additional pod volumes. |
| services.api.workload.preStopSleepSeconds | int | `0` | Extra sleep before SIGTERM, via a preStop hook, so endpoint removal can propagate (Deployment mode only). Requires `/bin/sh` and `sleep` in the image; must be lower than `terminationGracePeriodSeconds`. |
| services.api.workload.replicas | int | `1` | Replica count (Deployment mode only). |
| services.api.workload.strategy.maxSurge | int | `1` | Maximum surge pods during a rolling update (integer or percent string). |
| services.api.workload.strategy.maxUnavailable | int | `0` | Maximum unavailable pods during a rolling update (integer or percent string). |
| services.api.workload.terminationGracePeriodSeconds | int | `300` | Seconds the kubelet allows the pod to terminate (Deployment mode only). |
| services.api.workload.type | string | `"Knative"` | Workload kind: `Knative` or `Deployment`. |

## Long-Running Services (Deployment Workload)

Knative is the default workload, and it fits request/response services well. For connections that outlive a request, such as websocket servers or streaming gateways, Knative's request timeout (`services.<key>.scaling.timeoutSeconds`, default `300`) and scale-to-zero behavior are the wrong tool. Set `services.<key>.workload.type: Deployment` to render a standard `apps/v1` Deployment behind a core `v1` Service instead:

```yaml
services:
  gateway:
    image:
      repository: ghcr.io/my-org/websocket-gateway
      tag: v1.0.0
    workload:
      type: Deployment
      replicas: 2
    service:
      type: LoadBalancer
      port: 80
```

Every service entry with `workload.type: Deployment` renders a Deployment and a core Service, plus a `policy/v1` PodDisruptionBudget when `services.<key>.podDisruptionBudget.enabled` is `true`. All keys are listed in the generated values table above. Knative remains the default; existing entries render exactly as before.

### Metadata mapping

*   `services.<key>.annotations` and `services.<key>.labels` apply to the Deployment's metadata (mirroring the Knative Service mapping). Since the Deployment and the core Service both carry the shared service label set, `services.<key>.labels` also lands on the Service.
*   `services.<key>.podAnnotations` apply to the Pod template.
*   `services.<key>.service.annotations` and `services.<key>.service.labels` apply to the core Service only (not the Deployment or its pods). Cloud load-balancer idle-timeout annotations belong here.

### Graceful shutdown

On pod termination the order is: endpoint removal from the Service, then the `preStop` hook (if any), then `SIGTERM`, then `SIGKILL` when `terminationGracePeriodSeconds` runs out. Your app must handle `SIGTERM` to drain; otherwise the connection is cut.

Keep `terminationGracePeriodSeconds` comfortably larger than `preStopSleepSeconds` plus your drain window. The validators require `preStopSleepSeconds < terminationGracePeriodSeconds` when both are greater than zero.

`preStopSleepSeconds > 0` renders `exec: ["/bin/sh", "-c", "sleep N"]`, so it needs a shell and a `sleep` binary in the image. Keep it `0` for distroless images and drain in-app instead.

### Session affinity

`sessionAffinity` defaults to `None`. A websocket TCP connection is already pinned to a pod for its lifetime, so affinity mainly affects reconnects. `ClientIP` can stick clients to a pod that is draining during a rollout, so enable it only when your app needs sticky reconnects.

### External traffic policy

`externalTrafficPolicy` is only meaningful for `NodePort` and `LoadBalancer` services. `Local` preserves the client source IP and avoids an extra hop, but it can drop connections when a node has no ready endpoints. Use it only with enough replicas to keep every node's endpoints populated.

### Load-balancer idle timeouts

Idle timeouts are set with cloud-specific annotations on the core Service:

```yaml
services:
  gateway:
    service:
      annotations:
        # AWS NLB
        service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: "3600"
        # GCP (the timeout itself lives in the referenced BackendConfig)
        cloud.google.com/backend-config: '{"default": "gateway-idle"}'
```

### PodDisruptionBudget semantics

A PodDisruptionBudget governs **voluntary** evictions only, which means node drains and cluster upgrades. It does not govern rolling updates (those follow `workload.strategy`), and it does not stop a node failure or a crash from taking pods down.

### Limitations

*   `scaling.*` is Knative-only. It is ignored when `workload.type: Deployment`; use `workload.replicas` for the replica count.
*   `flagger.enabled` is not supported with `workload.type: Deployment` and fails rendering (the Canary class targets Knative Services).
*   A Kafka source `sink` cannot reference a Deployment-backed service, because a plain Kubernetes Service is not Knative-addressable. Point `kafka.sources.<key>.sink` at a Knative service.
*   The Kyverno scaling guardrails cover Knative Services only; they do not police Deployment-backed services.
*   Changing `nameOverride`, the map key, or switching `workload.type` on an existing release recreates or replaces resources. The Deployment's `selector` is immutable, so a rename cannot be applied in place.

## Kafka Event Sources (Map)

Each key in `kafka.sources:` defines a KafkaSource. The `sink` field must reference a valid key in the `services` map (validated at render time). When `kafka.broker.enabled: true`, sources sink to the Broker instead and must not set `sink`.

| Key | Description | Default |
|-----|-------------|---------|
| `kafka.sources.<key>.topic` | Kafka topic name | `"events"` |
| `kafka.sources.<key>.sink` | **Required unless `kafka.broker.enabled` is true.** Key from the `services` map, or omit to sink to the Broker | — |
| `kafka.sources.<key>.consumerGroup` | Consumer group (defaults to source name) | `""` |
| `kafka.sources.<key>.bootstrapServers` | List of bootstrap servers | `[kafka.kafka.svc:9092]` |
| `kafka.sources.<key>.consumers` | Concurrent consumers per replica | `3` |
| `kafka.sources.<key>.initialOffset` | `latest` or `earliest` | `latest` |
| `kafka.sources.<key>.delivery.retry` | Delivery retry count | `5` |
| `kafka.sources.<key>.delivery.backoffPolicy` | `linear` or `exponential` | `exponential` |
| `kafka.sources.<key>.delivery.backoffDelay` | Backoff delay (ISO 8601) | `PT1S` |
| `kafka.sources.<key>.dlq.enabled` | Enable Dead Letter Queue service | `true` |
| `kafka.sources.<key>.dlq.image` | DLQ container image | `event_display` |
| `kafka.sources.<key>.net.tls.enabled` | Enable TLS for the KafkaSource connection | `false` |
| `kafka.sources.<key>.net.tls.caCertSecret` | Secret containing the broker CA certificate | `""` |
| `kafka.sources.<key>.net.tls.caCertKey` | CA certificate key within the Secret | `ca.crt` |
| `kafka.sources.<key>.net.tls.certSecret` | Secret containing the client certificate (TLS-only/mTLS) | `""` |
| `kafka.sources.<key>.net.tls.certKey` | Client certificate key within the Secret | `tls.crt` |
| `kafka.sources.<key>.net.tls.keySecret` | Secret containing the client private key (TLS-only/mTLS) | `""` |
| `kafka.sources.<key>.net.tls.keyKey` | Client private key key within the Secret | `tls.key` |
| `kafka.sources.<key>.net.sasl.enabled` | Enable SASL for the KafkaSource connection | `false` |
| `kafka.sources.<key>.net.sasl.mechanism` | `PLAIN`, `SCRAM-SHA-256`, or `SCRAM-SHA-512` | `SCRAM-SHA-512` |
| `kafka.sources.<key>.net.sasl.userSecret` | Secret containing the SASL username | `""` |
| `kafka.sources.<key>.net.sasl.userKey` | Username key within the Secret | `user` |
| `kafka.sources.<key>.net.sasl.passwordSecret` | Secret containing the SASL password | `""` |
| `kafka.sources.<key>.net.sasl.passwordKey` | Password key within the Secret | `password` |

### TLS and SASL

`kafka.sources.<key>.net` renders the upstream Knative KafkaSource `spec.net` block. Only enabled sections render; an empty `net` block is never emitted.

*   **TLS + SASL (SASL_SSL):** set `net.tls.enabled` and `net.sasl.enabled`, provide `net.tls.caCertSecret` and the SASL user/password Secrets. Client certificate and key are optional.
*   **TLS only:** Knative treats this as mTLS. `net.tls.certSecret` and `net.tls.keySecret` are required.
*   **SASL only:** set `net.sasl.enabled` and provide `userSecret` / `passwordSecret`; no TLS block renders.
*   The chart creates `<release>-<key>-kafka-sasl-type` with `saslType: <mechanism>` and references it from `spec.net.sasl.type`. Managed clusters also add the managed username to that Secret.
*   `net.sasl.mechanism` defaults to `SCRAM-SHA-512`; upstream defaults to `PLAIN` when the type is omitted.

### Kafka Broker and Triggers (Opt-In)

`kafka.broker.enabled: true` renders a `Broker` (`eventing.knative.dev/v1`, Kafka class) and a per-release `ConfigMap` containing `bootstrap.servers`, `default.topic.partitions`, and `default.topic.replication.factor`. Sources with no `sink` deliver to the Broker; setting `sink` while the broker is enabled fails rendering.

`kafka.triggers` maps trigger names to subscribers. Each entry requires `subscriber` (a key in `services`) and supports legacy `filter` attributes or modern `filters`, delivery settings, annotations, and an optional DLQ. The generated values table lists the `kafka.broker` surface; per-entry trigger fields are documented here because `kafka.triggers` ships empty.

When the Broker connects to an authenticated Kafka cluster, set `kafka.broker.config.authSecretName` to a Secret containing the keys expected by the Knative Kafka Broker: `sasl.mechanism`, `user`, `password`, `security.protocol`, and `ca.crt` when TLS is enabled.

### Managed Kafka (Opt-In)

Set `kafka.cluster.enabled: true` and choose `provider: strimzi` or `provider: redpanda` to render a managed Kafka cluster and derive the KafkaSource/Broker bootstrap endpoint. The chart renders CRs only; install the operator and CRDs separately.

*   **Strimzi:** renders `KafkaNodePool` + `Kafka`, and `KafkaTopic` / `KafkaUser` when `topics.create` / `auth.type: scram` are enabled. Requires Strimzi >= 1.0 and Kubernetes >= 1.32. `kafka.cluster.name` must be a DNS-1123 label of at most 47 characters so derived Service names stay within 63.
*   **Redpanda:** renders `Redpanda`, `Topic`, and `User`. Requires the Redpanda operator >= 26.2 and a user-supplied superuser Secret (`kafka.cluster.redpanda.sasl.secretRef`) for SCRAM.
*   **Bootstrap:** Strimzi `<cluster>-kafka-bootstrap.<namespace>.svc.cluster.local:9092|9093`; Redpanda `<cluster>.<namespace>.svc.cluster.local:9093`.
*   **TLS:** managed Strimzi derives `<cluster>-cluster-ca-cert` (`ca.crt`); Redpanda derives `<cluster>-default-cert` (`ca.crt`). Redpanda TLS requires cert-manager. Every source must set `net.tls.enabled: true` when `kafka.cluster.tls.enabled` is true; otherwise rendering fails.
*   **SASL:** set `kafka.sources.<key>.net.sasl.enabled: true` when `auth.type: scram`. The chart derives the per-source SASL type Secret and the managed user password Secret. Enabling SASL while `auth.type: none` fails rendering rather than producing dangling references.
*   **Explicit bootstrapServers:** setting a source or broker bootstrap server while the managed cluster is enabled fails rendering rather than silently overriding it.
*   **Replication:** topic/broker replication factors clamp to `min(replicas, 3)` for Strimzi and `1`/`3` for Redpanda.
*   **Operators:** the chart never installs Strimzi, Redpanda, Knative, or their CRDs. `make install-strimzi-crds` and `make install-redpanda-crds` install CRDs only; `hack/install-strimzi-operator.sh` and `hack/install-redpanda-operator.sh` install the operators for Kind e2e.

## PingSource Event Sources (Map)

Each key in `pingsources:` defines a PingSource. The `sink` field must reference a valid key in the `services` map (validated at render time).

| Key | Description | Default |
|-----|-------------|---------|
| `pingsources.<key>.schedule` | Cron schedule for the emitted event | `"0 * * * *"` |
| `pingsources.<key>.timezone` | IANA time zone for the schedule | `"UTC"` |
| `pingsources.<key>.data` | CloudEvent payload | `""` |
| `pingsources.<key>.contentType` | Payload content type | `"application/json"` |
| `pingsources.<key>.sink` | **Required.** Key from the `services` map | — |
| `pingsources.<key>.ceOverrides.extensions` | Map of custom CloudEvent extension attributes (never `type`) | `{}` |

Each entry renders a PingSource named `<release>-<key>-ping-source`. Every event has the fixed CloudEvent type `dev.knative.sources.ping`. `ceOverrides.extensions` can add or override extension attributes, but it cannot change `type`; the validator rejects a `type` key there.

The chart defaults differ from the Knative API defaults: the chart uses `0 * * * *` (hourly) and `UTC`, while the Knative API defaults to `* * * * *` (every minute) and the cluster's system time zone. Set `schedule` and `timezone` explicitly if you depend on the API defaults.

The sink is rendered as a Knative Service `ref` with no path, so events are delivered to the service's root path (`/`). There is no per-entry sink path option; serve the handler at `/` or route to it from there.

```yaml
pingsources:
  scheduled:
    schedule: "0 * * * *"
    timezone: "UTC"
    data: '{"hello":"world"}'
    contentType: application/json
    sink: api
    ceOverrides:
      extensions:
        my-extension: value
```

## Object Buckets (Ceph RGW)

The chart can provision S3 buckets on Ceph RGW (or any object store fronted by `lib-bucket-provisioner`) so Postgres backups and Dragonfly snapshots land on object storage with no hand-created credential Secrets. Declare buckets in a top-level `objectBuckets` map; the chart renders one `ObjectBucketClaim` per entry and wires any consumer that references it. The feature is off by default: leave `objectBuckets` empty and rendering is unchanged.

The chart references an existing StorageClass by name. It never renders a StorageClass.

### Prerequisites

*   The `lib-bucket-provisioner` CRDs. Install them with `make install-object-bucket` (the target installs the `ObjectBucketClaim` and `ObjectBucket` CRDs).
*   An existing bucket StorageClass for your object store. For Rook/Ceph it looks like this:

    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: ceph-bucket
    provisioner: rook-ceph.ceph.rook.io/bucket
    reclaimPolicy: Retain
    parameters:
      objectStoreName: ceph-objectstore
      objectStoreNamespace: rook-ceph
    ```

    The provisioner is `<objectStoreNamespace>.ceph.rook.io/bucket` (here `rook-ceph.ceph.rook.io/bucket`), and `objectStoreName`/`objectStoreNamespace` identify the CephObjectStore. The chart uses `metadata.name` only.
*   An RGW endpoint URL reachable from the cluster, for example `http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80`. Set it as `endpointURL` on the bucket entry.

### Bucket values

Each key under `objectBuckets` defines one bucket:

| Key | Description | Default |
|-----|-------------|---------|
| `objectBuckets.<key>.storageClassName` | **Required.** Name of an existing bucket StorageClass | *(required)* |
| `objectBuckets.<key>.bucketName` | S3 bucket name. Immutable once the claim binds | `<release>-<key>` (sanitized) |
| `objectBuckets.<key>.endpointURL` | Full endpoint URL. CNPG uses it literally; Dragonfly derives the host and `--s3_use_https` from the scheme | `""` |
| `objectBuckets.<key>.region` | Injected as `AWS_REGION` for Dragonfly S3 snapshots; ignored on the Postgres path | `""` |

```yaml
objectBuckets:
  postgres-backups:
    storageClassName: ceph-bucket
    endpointURL: http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80
  dragonfly-snapshots:
    storageClassName: ceph-bucket
    endpointURL: http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80
    region: us-east-1
```

### PostgreSQL backups

Reference a bucket from `postgres.backup.objectStore.bucketRef`:

```yaml
postgres:
  enabled: true
  backup:
    enabled: true
    objectStore:
      bucketRef: postgres-backups
```

When `bucketRef` is set the chart derives:

*   `destinationPath`, defaulting to `s3://<bucketName>/`. An explicit `destinationPath` wins.
*   `endpointURL`, defaulting to the bucket entry's `endpointURL`. An explicit `endpointURL` wins.
*   `s3Credentials`, defaulting to the claim-named Secret with keys `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

If any `s3Credentials` field is set explicitly (`secretName`, `accessKeyIdKey`, or `secretAccessKeyKey`), the whole `s3Credentials` object is treated as consumer-owned and nothing is derived from the bucket. That keeps credentials from being mixed. Manual external-S3 setups (an explicit `endpointURL`, `destinationPath`, and `s3Credentials`) keep working exactly as before whenever `bucketRef` is unset.

The bucket entry's `region` is not used on this path.

### Dragonfly snapshots

Reference a bucket from `dragonfly.snapshot.bucketRef`:

```yaml
dragonfly:
  enabled: true
  snapshot:
    enabled: true
    bucketRef: dragonfly-snapshots
```

When `bucketRef` is set the chart derives:

*   `dir`, defaulting to `s3://<bucketName>/`. An explicit `dir` wins.
*   `--s3_endpoint=<host:port>` with the URL scheme stripped (Dragonfly v1.21.x needs a scheme-less endpoint).
*   `--s3_use_https=true|false`, from the endpoint scheme (`https://` gives `true`, `http://` gives `false`).
*   env `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as `secretKeyRef`s to the claim-named Secret, plus `AWS_REGION` from the entry's `region` when it is set.

`bucketRef` and `existingPersistentVolumeClaimName` are mutually exclusive. User-supplied `dragonfly.env` entries and `dragonfly.args` flags are never duplicated: the chart appends a derived item only when no entry with the same name or flag is present.

### Consuming a bucket from an app

Each `ObjectBucketClaim` makes the provisioner create, in the release namespace, a Secret and a ConfigMap named after the claim (`<release>-<key>`):

*   Secret keys: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
*   ConfigMap keys: `BUCKET_HOST`, `BUCKET_PORT`, `BUCKET_NAME`

Reach them through the existing per-service passthrough, with no new API:

```yaml
services:
  api:
    envFrom:
      - secretRef:
          name: test-postgres-only-postgres-backups
      - configMapRef:
          name: test-postgres-only-postgres-backups
    volumes:
      - name: bucket-creds
        secret:
          secretName: test-postgres-only-postgres-backups
```

### Warnings

*   **Deletion risk.** The referenced StorageClass's `reclaimPolicy` governs the bucket. With `reclaimPolicy: Delete`, `helm uninstall` deletes the bucket and its backups. Prefer `Retain` for backup buckets.
*   **Unique, immutable names.** Bucket names are unique per object store across all namespaces, and `bucketName` is immutable once the claim binds. Set an explicit `bucketName` when several releases share one object store.
*   **Cost.** Provisioned buckets consume real RGW capacity and egress.
*   **Secret scope.** The claim Secret is a plain namespaced Secret. Anyone who can read the namespace can read it, and there is no External Secrets Operator integration.

### Switching from minio/rustfs

Drop the manual endpoint and credential Secret and point at a bucket instead. Before:

```yaml
postgres:
  enabled: true
  backup:
    enabled: true
    objectStore:
      destinationPath: s3://postgres-backups/
      endpointURL: http://minio.minio.svc:9000
      s3Credentials:
        secretName: postgres-backup-storage
        accessKeyIdKey: ACCESS_KEY_ID
        secretAccessKeyKey: ACCESS_SECRET_KEY
```

After (this is `examples/postgres-only/values.yaml`):

```yaml
objectBuckets:
  postgres-backups:
    storageClassName: "ceph-bucket"
    endpointURL: "http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80"

postgres:
  enabled: true
  version: "16"
  instances: 2
  storage:
    size: "100Gi"
    storageClassName: "standard"
  backup:
    enabled: true
    schedule: "0 3 * * *"
    retentionPolicy: "14d"
    objectStore:
      bucketRef: "postgres-backups"
  monitoring:
    enabled: true
```

## Kyverno Admission Policies (Opt-In)

The chart can render three Kyverno `NamespacedValidatingPolicy` resources that act as a defense-in-depth admission guardrail on top of the render-time validators above. They are disabled by default; enable them with:

```yaml
kyverno:
  enabled: true
  scaling:
    enabled: true
```

Policies render into the release namespace (`metadata.namespace: <Release.Namespace>`) and, being namespaced Kyverno policies, apply to **all** matching resources in that namespace — not only the resources created by this release. Each policy sets `failurePolicy: Fail` and targets one resource type: Knative Services (`serving.knative.dev/v1` — scaling annotations, `containerConcurrency`, `timeoutSeconds`), CNPG Clusters (`postgresql.cnpg.io/v1` — `spec.instances` 1–16), and Dragonfly instances (`dragonflydb.io/v1alpha1` — `spec.replicas` 1–16 and PDB bounds).

`validationActions` controls enforcement: `Deny` (default) blocks non-compliant requests; `Audit` only records them. The policy `apiVersion` defaults to `policies.kyverno.io/v1beta1` (Kyverno >= 1.16); set it to `policies.kyverno.io/v1` on Kyverno >= 1.17.

The relevant values (`kyverno.enabled`, `kyverno.scaling.enabled`, `kyverno.scaling.apiVersion`, `kyverno.scaling.validationActions`) are listed in the generated values table above.

## Migration from v0.1.x

v0.2.0 is a **breaking change**. The `knativeService:` and top-level `flagger:` / `kafka:` keys have been replaced.

### Key changes

| v0.1.x | v0.2.0 |
|--------|--------|
| `knativeService.image.repository` | `services.<key>.image.repository` |
| `knativeService.scaling.*` | `services.<key>.scaling.*` |
| `flagger.enabled` | `services.<key>.flagger.enabled` |
| `kafka.enabled` | Remove — presence of `kafka.sources` entries enables Kafka |
| `kafka.source.topic` | `kafka.sources.<key>.topic` |
| `kafka.source.sink` (implicit) | `kafka.sources.<key>.sink` (explicit, validated) |

### Migration steps

1. Replace `knativeService:` with a named entry under `services:`:
   ```yaml
   # Before (v0.1.x)
   knativeService:
     image:
       repository: ghcr.io/org/my-app
       tag: v1.0.0

   # After (v0.2.0)
   services:
     app:
       image:
         repository: ghcr.io/org/my-app
         tag: v1.0.0
   ```

2. Move `flagger:` inside the service entry:
   ```yaml
   # Before
   flagger:
     enabled: true

   # After
   services:
     app:
       flagger:
         enabled: true
   ```

3. Convert `kafka:` to `kafka.sources:` map with explicit `sink`:
   ```yaml
   # Before
   kafka:
     enabled: true
     source:
       topic: my-events

   # After
   kafka:
     sources:
       events:
         topic: my-events
         sink: app    # must match a key in services
   ```

## Examples

The [examples/](../../../examples/) directory contains reference implementations:

*   **minimal** — Single Knative service with env vars and resource limits.
*   **full-stack** — Multi-service deployment with PostgreSQL, Kafka, DragonflyDB, and Flagger.
*   **postgres-only** — API service with CloudNativePG integration.
*   **kafka-consumer** — Consumer service with KafkaSource and DLQ.
*   **kafka-broker** — Kafka Broker with filtered Triggers and a broker-sink KafkaSource.
*   **kafka-source-net** — KafkaSource with TLS and SASL against an external Kafka cluster.
*   **kafka-strimzi** — Managed Strimzi cluster with TLS, SCRAM, topics, users, and a shared project topic.
*   **kafka-redpanda** — Managed Redpanda cluster with managed topics and a shared project topic.
*   **dragonfly-cache** — Knative service with DragonflyDB caching, auth, TLS, and snapshots.
*   **longrunning-websocket** — Websocket gateway as a standard Deployment workload with a ClientIP core Service, a PodDisruptionBudget, and a preStop drain delay.

## CI/CD

The repository uses GitHub Actions for automated quality assurance:

*   **Lint and Test**: Runs `helm lint`, validates `values.yaml` against a JSON schema, renders templates for all examples, and executes unit tests. It also runs a PR-level Kyverno policy gate that renders the opt-in admission policies and checks the `test/kyverno/` fixtures with the Kyverno CLI, and a docs check that fails when this README is out of sync with `values.yaml`.
*   **Release**: Triggers when a chart's `Chart.yaml` version changes on `main` (diff-detected on each push), packaging and pushing that chart to GHCR as an OCI artifact and tagging it `<chart>-v<version>` (for example `ksvc-v0.10.0`). Pushing a matching `<chart>-v<version>` tag also triggers a release.
*   **Integration Test**: Nightly Kind cluster deployment that verifies CRD compatibility and server-side dry-runs for all example configurations. A `kyverno-guardrails-e2e` job installs Kyverno, applies the fixtures in `test/kyverno/`, and asserts the guardrail policies deny invalid scaling/replica specs while admitting compliant ones.

## Testing

Unit tests use the `helm-unittest` plugin and live in the `test-chart` wrapper.

```bash
cd charts/library/ksvc
helm dependency build test-chart
helm unittest test-chart
```

## Development

1.  Add new templates to `charts/library/ksvc/templates/classes/`.
2.  Register the new class in `charts/library/ksvc/templates/loader/_generate.tpl`.
3.  Add corresponding unit tests in `charts/library/ksvc/test-chart/tests/`.
4.  Update example configurations in `examples/` to reflect new capabilities.
5.  Run `make lint`, `make test`, and `make docs` before submitting changes.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
