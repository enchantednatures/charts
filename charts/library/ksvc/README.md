# ksvc

Helm library chart for Knative services with integrated CloudNativePG, Kafka, and Flagger.

## Overview

This library chart provides a standardized way to deploy serverless applications on Kubernetes using Knative. It replaces repetitive boilerplate by rendering a Knative Service alongside optional dependencies like PostgreSQL clusters, Kafka event sources, and canary release configurations.

## Architecture

The chart follows a library pattern to ensure consistency across multiple services:

1.  **Loader**: The consumer chart calls `ksvc.loader.generate` from its templates.
2.  **Defaults**: The library applies opinionated defaults using `mustMergeOverwrite` to compensate for Helm's lack of library value merging.
3.  **Classes**: Dedicated template classes manage specific resource groups (Knative, CNPG, Kafka, Flagger).
4.  **Resources**: Standard Kubernetes and Custom Resource manifests are rendered based on the enabled features.

## Quick Start

1.  Create a new Helm chart to consume the library:
    ```bash
    helm create my-service
    rm -rf my-service/templates/*
    ```

2.  Add the dependency to `Chart.yaml`:
    ```yaml
    dependencies:
      - name: ksvc
        version: 0.1.0
        repository: oci://ghcr.io/enchantednatures/charts
    ```

3.  Create `my-service/templates/common.yaml`:
    ```yaml
    {{- include "ksvc.loader.generate" . }}
    ```

4.  Configure `values.yaml`:
    ```yaml
    knativeService:
      image:
        repository: ghcr.io/my-org/my-service
        tag: v1.0.0
    ```

## Resources Rendered

| Feature | Resources Rendered |
|---------|-------------------|
| **Base** | Knative Service |
| **PostgreSQL** | Cluster, Pooler, ObjectStore, ScheduledBackup, PodMonitor, PrometheusRule |
| **Kafka** | KafkaSource, Knative Service (DLQ) |
| **DragonflyDB** | Dragonfly |
| **Flagger** | Canary |

## Values Reference

### Global Settings
| Key | Description | Default |
|-----|-------------|---------|
| `global.nameOverride` | Override chart name | `""` |
| `global.fullnameOverride` | Override fullname | `""` |
| `global.labels` | Labels for all resources | `{}` |
| `global.annotations` | Annotations for all resources | `{}` |

### Knative Service
| Key | Description | Default |
|-----|-------------|---------|
| `knativeService.image.repository` | Container image repository | `""` |
| `knativeService.image.tag` | Container image tag | `"latest"` |
| `knativeService.image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `knativeService.image.fluxImagePolicy` | Flux image policy annotation | `""` |
| `knativeService.scaling.minScale` | Minimum replicas | `1` |
| `knativeService.scaling.maxScale` | Maximum replicas | `10` |
| `knativeService.scaling.target` | Scaling target | `100` |
| `knativeService.scaling.containerConcurrency` | Max requests per pod | `100` |
| `knativeService.scaling.timeoutSeconds` | Request timeout | `300` |
| `knativeService.scaling.class` | Autoscaler class | `""` |
| `knativeService.resources` | Container CPU/Memory resources | See values.yaml |
| `knativeService.port` | Container port | `8080` |
| `knativeService.probes` | Liveness and Readiness probes | See values.yaml |
| `knativeService.env` | List of environment variables | `[]` |
| `knativeService.envFrom` | envFrom sources (Secrets/ConfigMaps) | `[]` |
| `knativeService.securityContext` | Pod security settings | See values.yaml |
| `knativeService.volumeMounts` | Container volume mounts | `[]` |
| `knativeService.volumes` | Pod volumes | `[]` |
| `knativeService.podAnnotations` | Annotations for the Pod | Prometheus scraping enabled |
| `knativeService.annotations` | Annotations for the Service | Prometheus scraping enabled |
| `knativeService.labels` | Labels for the Service | `{}` |

### CloudNativePG PostgreSQL
| Key | Description | Default |
|-----|-------------|---------|
| `postgres.enabled` | Enable PostgreSQL cluster | `false` |
| `postgres.version` | PostgreSQL version | `"16"` |
| `postgres.instances` | Number of database instances | `3` |
| `postgres.parameters` | Postgres configuration parameters | TLS 1.3, standard buffers |
| `postgres.sharedPreloadLibraries` | Libraries to preload | `[pg_stat_statements]` |
| `postgres.postInitSQL` | SQL commands to run after init | `[]` |
| `postgres.resources` | Cluster resource limits/requests | 1 CPU, 2Gi RAM requests |
| `postgres.storage.size` | PVC size | `"200Gi"` |
| `postgres.storage.storageClassName` | PVC storage class | `"standard"` |
| `postgres.pooler.enabled` | Enable PgBouncer pooler | `true` |
| `postgres.pooler.instances` | Number of pooler replicas | `3` |
| `postgres.pooler.type` | Pooler type (rw/ro) | `rw` |
| `postgres.pooler.poolMode` | session/transaction | `transaction` |
| `postgres.backup.enabled` | Enable WAL archiving and backups | `true` |
| `postgres.backup.schedule` | Cron schedule for backups | `"0 2 * * *"` |
| `postgres.backup.retentionPolicy` | Retention period | `"30d"` |
| `postgres.backup.objectStore` | S3/Object storage configuration | See values.yaml |
| `postgres.monitoring.enabled` | Enable PodMonitor and Alerts | `true` |
| `postgres.monitoring.alerts` | Thresholds for Prometheus rules | See values.yaml |

### Kafka Event Source
| Key | Description | Default |
|-----|-------------|---------|
| `kafka.enabled` | Enable Kafka source | `false` |
| `kafka.source.topic` | Kafka topic name | `"events"` |
| `kafka.source.consumerGroup` | Kafka consumer group | `""` |
| `kafka.source.bootstrapServers` | List of bootstrap servers | `[kafka.kafka.svc:9092]` |
| `kafka.source.consumers` | Concurrent consumers per replica | `3` |
| `kafka.source.initialOffset` | latest/earliest | `latest` |
| `kafka.delivery.retry` | Delivery retry count | `5` |
| `kafka.delivery.backoffPolicy` | linear/exponential | `exponential` |
| `kafka.delivery.backoffDelay` | Backoff delay (ISO8601) | `PT1S` |
| `kafka.dlq.enabled` | Enable Dead Letter Queue | `true` |
| `kafka.dlq.image` | DLQ event display image | `event_display` |

### Flagger Canary Release
| Key | Description | Default |
|-----|-------------|---------|
| `flagger.enabled` | Enable Flagger canary | `false` |
| `flagger.analysis.interval` | Check interval | `"1m"` |
| `flagger.analysis.threshold` | Failure threshold | `5` |
| `flagger.analysis.maxWeight` | Maximum traffic weight | `50` |
| `flagger.analysis.stepWeight` | Traffic increment step | `10` |
| `flagger.metrics` | Success/Latency thresholds | 99% success, 500ms p99 |
| `flagger.loadTest.enabled` | Enable k6 load testing | `true` |
| `flagger.loadTest.webhookUrl` | k6 loadtester service URL | `""` |

### DragonflyDB Cache Cluster
| Key | Description | Default |
|-----|-------------|---------|
| `dragonfly.enabled` | Enable DragonflyDB cluster | `false` |
| `dragonfly.replicas` | Total instances including master | `3` |
| `dragonfly.image` | Dragonfly container image | `docker.dragonflydb.io/dragonflydb/dragonfly` |
| `dragonfly.imageTag` | Container image tag | `"v1.21.2"` |
| `dragonfly.args` | Extra CLI args (e.g. `--cluster_mode=emulated`) | `[]` |
| `dragonfly.env` | Environment variables | `[]` |
| `dragonfly.resources` | Container CPU/Memory resources | 500m/512Mi requests |
| `dragonfly.authentication.passwordFromSecret.name` | Secret name for auth password | `""` |
| `dragonfly.authentication.passwordFromSecret.key` | Secret key for auth password | `password` |
| `dragonfly.authentication.clientCaCertSecret.name` | Secret name for mTLS client CA | `""` |
| `dragonfly.tls.secretName` | TLS Secret (tls.crt/tls.key) | `""` |
| `dragonfly.snapshot.enabled` | Enable snapshot persistence | `false` |
| `dragonfly.snapshot.cron` | Snapshot cron schedule | `"0 */6 * * *"` |
| `dragonfly.snapshot.enableOnMasterOnly` | Snapshot only on master | `true` |
| `dragonfly.snapshot.dir` | S3 backup path (mutually exclusive with PVC) | `""` |
| `dragonfly.snapshot.existingPersistentVolumeClaimName` | Use existing PVC | `""` |
| `dragonfly.snapshot.storage.size` | PVC size (when dir/existingPVC empty) | `"10Gi"` |
| `dragonfly.snapshot.storage.storageClassName` | PVC storage class | `""` |
| `dragonfly.serviceSpec.type` | Kubernetes Service type | `ClusterIP` |
| `dragonfly.pdb.minAvailable` | Min available pods for PDB | `2` |
| `dragonfly.pdb.maxUnavailable` | Max unavailable pods for PDB | `0` |
| `dragonfly.affinity` | Pod affinity rules | `{}` |
| `dragonfly.tolerations` | Pod tolerations | `[]` |
| `dragonfly.topologySpreadConstraints` | Topology spread constraints | `[]` |
| `dragonfly.nodeSelector` | Node selector | `{}` |
| `dragonfly.serviceAccountName` | Service account name | `""` |
| `dragonfly.priorityClassName` | Priority class name | `""` |

## Examples

The [examples/](../../../examples/) directory contains several reference implementations:

*   **minimal**: A basic Knative service with environment variables and resource limits.
*   **full-stack**: A complete deployment including PostgreSQL (with backups), Kafka event source (with DLQ), DragonflyDB cache, and Flagger canary analysis.
*   **postgres-only**: Focuses on the CloudNativePG integration for API services requiring state.
*   **kafka-consumer**: Demonstrates scaling a consumer service based on Kafka topic throughput.
*   **dragonfly-cache**: Demonstrates a Knative service with DragonflyDB for caching, including auth, TLS, and PVC snapshots.

## CI/CD

The repository uses GitHub Actions for automated quality assurance:

*   **Lint and Test**: Runs `helm lint`, validates `values.yaml` against a JSON schema, renders templates for all examples, and executes unit tests.
*   **Release**: Triggers on version tags (`v*`) to package and push the chart to GHCR as an OCI artifact.
*   **Integration Test**: Nightly Kind cluster deployment that verifies CRD compatibility and server-side dry-runs for all example configurations.

## Testing

Unit tests are written using the `helm-unittest` plugin and located in the `test-chart` wrapper.

To run tests locally:

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
5.  Run `helm lint` and `helm unittest` before submitting changes.
