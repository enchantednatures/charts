# ksvc

Helm library chart for deploying **multiple Knative services** with integrated CloudNativePG, Kafka event sources, DragonflyDB, and Flagger canary releases.

## Overview

This library chart provides a standardized way to deploy serverless applications on Kubernetes using Knative Serving. Consumers define one or more services via a `services:` map, and the library renders all required Kubernetes and Custom Resource manifests.

Infrastructure resources (PostgreSQL, DragonflyDB) are shared globally across all services in the release, while Kafka event sources and Flagger canary configs are scoped per-source and per-service respectively.

## Architecture

```
Consumer Chart
  └── templates/common.yaml
        └── {{ include "ksvc.loader.generate" . }}
              ├── Validators (sink refs, required fields)
              ├── Per-service loop (services map)
              │     ├── Knative Service
              │     └── Flagger Canary (opt-in)
              ├── Per-source loop (kafka.sources map)
              │     ├── KafkaSource
              │     └── DLQ Knative Service (opt-in)
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
| KafkaSource | `<release>-<source-key>-kafka-source` |
| DLQ Service | `<release>-<source-key>-dlq` |
| CNPG Cluster | `<release>` (global) |
| Dragonfly | `<release>` (global) |
| ObjectBucketClaim | `<release>-<key>` (per `objectBuckets` entry) |

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
        version: 0.7.0
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
| **Flagger** | Canary (per service with `flagger.enabled: true`) | Per-service |
| **Kafka** | KafkaSource (per entry in `kafka.sources`) | Per-source |
| **Kafka DLQ** | Knative Service (per source with `dlq.enabled: true`) | Per-source |
| **PostgreSQL** | Cluster, Pooler, ObjectStore, ScheduledBackup, PodMonitor, PrometheusRule | Global |
| **DragonflyDB** | Dragonfly | Global |
| **Object Buckets (opt-in)** | ObjectBucketClaim (per entry in `objectBuckets`) | Global |
| **Kyverno (opt-in)** | NamespacedValidatingPolicy (3x: Knative scaling, CNPG instances, Dragonfly replicas/PDB) | Namespace |

## Values Reference

> **Schema validation note:** Helm does **not** validate a library chart's `values.schema.json` against consumer values passed through the loader — the schema above `ksvc`'s own install only. Render-time checks enforced by `_validators.tpl` (required fields, cross-references, cert-manager issuers) are the true enforcement; CI validates example values against this schema. If a "required" check matters, also rely on the validator behavior.
>
> Scaling and replica/instance counts are also enforced at render time by `_validators.tpl`: service scaling (`minScale`, `maxScale`, `target`, `containerConcurrency`, `timeoutSeconds`), postgres instances (1–16), pooler instances (≥ 1), and Dragonfly replicas (1–16). The Dragonfly PDB rules are checked too: `minAvailable` and `maxUnavailable` are mutually exclusive (setting both non-zero now fails rendering) and `minAvailable` must be `<= replicas`.

### Global Settings

| Key | Description | Default |
|-----|-------------|---------|
| `global.nameOverride` | Override chart name | `""` |
| `global.fullnameOverride` | Override fullname | `""` |
| `global.labels` | Labels applied to all resources | `{}` |
| `global.annotations` | Annotations applied to all resources | `{}` |

### Services (Map)

Each key in `services:` defines a Knative Service. The key becomes a name suffix: `<release>-<key>`. Set `nameOverride` to change the suffix or use `""` for no suffix.

| Key | Description | Default |
|-----|-------------|---------|
| `services.<key>.nameOverride` | Override the name suffix (replaces the map key). Set to `""` for no suffix. | *(not set — uses key)* |
| `services.<key>.image.repository` | Container image repository | `""` |
| `services.<key>.image.tag` | Container image tag | `"latest"` |
| `services.<key>.image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `services.<key>.image.fluxImagePolicy` | Flux image policy annotation | `""` |
| `services.<key>.scaling.minScale` | Minimum replicas | `1` |
| `services.<key>.scaling.maxScale` | Maximum replicas | `10` |
| `services.<key>.scaling.target` | Scaling target | `100` |
| `services.<key>.scaling.containerConcurrency` | Max concurrent requests per pod | `100` |
| `services.<key>.scaling.timeoutSeconds` | Request timeout | `300` |
| `services.<key>.scaling.class` | Autoscaler class | `""` |
| `services.<key>.scaling.metric` | Autoscaling metric (`concurrency`, `rps`; `cpu`/`memory`/custom require the HPA class). Empty falls back to the Knative default (`concurrency`) | `""` |
| `services.<key>.resources` | Container CPU/Memory resources | 100m/64Mi req, 500m/256Mi lim |
| `services.<key>.port` | Container port | `8080` |
| `services.<key>.probes.liveness` | Liveness probe config | See values.yaml |
| `services.<key>.probes.readiness` | Readiness probe config | See values.yaml |
| `services.<key>.env` | Environment variables | `[]` |
| `services.<key>.envFrom` | envFrom sources (Secrets/ConfigMaps) | `[]` |
| `services.<key>.securityContext` | Container security context | runAsNonRoot, readOnly, drop ALL |
| `services.<key>.volumeMounts` | Container volume mounts | `[]` |
| `services.<key>.volumes` | Pod volumes | `[]` |
| `services.<key>.podAnnotations` | Annotations for the Pod template | Prometheus scraping enabled |
| `services.<key>.annotations` | Annotations for the Knative Service | Prometheus scraping enabled |
| `services.<key>.labels` | Additional labels for the Knative Service | `{}` |

### Flagger Canary (Per-Service)

Flagger is configured inside each service entry.

| Key | Description | Default |
|-----|-------------|---------|
| `services.<key>.flagger.enabled` | Enable Flagger canary for this service | `false` |
| `services.<key>.flagger.analysis.interval` | Analysis check interval | `"1m"` |
| `services.<key>.flagger.analysis.threshold` | Failure threshold before rollback | `5` |
| `services.<key>.flagger.analysis.maxWeight` | Maximum traffic weight (%) | `50` |
| `services.<key>.flagger.analysis.stepWeight` | Traffic increment step (%) | `10` |
| `services.<key>.flagger.analysis.progressDeadlineSeconds` | Max seconds for canary progress | `120` |
| `services.<key>.flagger.metrics.successRateThreshold` | Min success rate (%) | `99` |
| `services.<key>.flagger.metrics.latencyP99ThresholdMs` | Max p99 latency (ms) | `500` |
| `services.<key>.flagger.metrics.prometheusAddress` | Prometheus server address | `http://prometheus.observability...` |
| `services.<key>.flagger.loadTest.enabled` | Enable k6 load testing | `true` |
| `services.<key>.flagger.loadTest.webhookUrl` | k6 loadtester webhook URL | `http://k6-loadtester.flagger-system/...` |
| `services.<key>.flagger.loadTest.vus` | Virtual users | `10` |
| `services.<key>.flagger.loadTest.duration` | Test duration | `"1m"` |

### Kafka Event Sources (Map)

Each key in `kafka.sources:` defines a KafkaSource. The `sink` field must reference a valid key in the `services` map (validated at render time).

| Key | Description | Default |
|-----|-------------|---------|
| `kafka.sources.<key>.topic` | Kafka topic name | `"events"` |
| `kafka.sources.<key>.sink` | **Required.** Key from the `services` map | — |
| `kafka.sources.<key>.consumerGroup` | Consumer group (defaults to source name) | `""` |
| `kafka.sources.<key>.bootstrapServers` | List of bootstrap servers | `[kafka.kafka.svc:9092]` |
| `kafka.sources.<key>.consumers` | Concurrent consumers per replica | `3` |
| `kafka.sources.<key>.initialOffset` | `latest` or `earliest` | `latest` |
| `kafka.sources.<key>.delivery.retry` | Delivery retry count | `5` |
| `kafka.sources.<key>.delivery.backoffPolicy` | `linear` or `exponential` | `exponential` |
| `kafka.sources.<key>.delivery.backoffDelay` | Backoff delay (ISO 8601) | `PT1S` |
| `kafka.sources.<key>.dlq.enabled` | Enable Dead Letter Queue service | `true` |
| `kafka.sources.<key>.dlq.image` | DLQ container image | `event_display` |

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
| `postgres.backup.objectStore.bucketRef` | Reference an `objectBuckets` entry to derive `destinationPath`, `endpointURL`, and claim-named S3 credentials | `""` |
| `postgres.monitoring.enabled` | Enable PodMonitor and Alerts | `true` |
| `postgres.monitoring.alerts` | Thresholds for Prometheus rules | See values.yaml |

### Object Buckets (Ceph RGW)

The chart can provision S3 buckets on Ceph RGW (or any object store fronted by `lib-bucket-provisioner`) so Postgres backups and Dragonfly snapshots land on object storage with no hand-created credential Secrets. Declare buckets in a top-level `objectBuckets` map; the chart renders one `ObjectBucketClaim` per entry and wires any consumer that references it. The feature is off by default: leave `objectBuckets` empty and rendering is unchanged.

The chart references an existing StorageClass by name. It never renders a StorageClass.

#### Prerequisites

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

#### Bucket values

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

#### PostgreSQL backups

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

#### Dragonfly snapshots

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

#### Consuming a bucket from an app

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

#### Warnings

*   **Deletion risk.** The referenced StorageClass's `reclaimPolicy` governs the bucket. With `reclaimPolicy: Delete`, `helm uninstall` deletes the bucket and its backups. Prefer `Retain` for backup buckets.
*   **Unique, immutable names.** Bucket names are unique per object store across all namespaces, and `bucketName` is immutable once the claim binds. Set an explicit `bucketName` when several releases share one object store.
*   **Cost.** Provisioned buckets consume real RGW capacity and egress.
*   **Secret scope.** The claim Secret is a plain namespaced Secret. Anyone who can read the namespace can read it, and there is no External Secrets Operator integration.

#### Switching from minio/rustfs

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
| `dragonfly.snapshot.bucketRef` | Reference an `objectBuckets` entry for S3 snapshots (derives `dir`, credential env, `--s3_endpoint`, `--s3_use_https`); mutually exclusive with `existingPersistentVolumeClaimName` | `""` |
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

### Kyverno Admission Policies (Opt-In)

The chart can render three Kyverno `NamespacedValidatingPolicy` resources that act as a defense-in-depth admission guardrail on top of the render-time validators above. They are disabled by default; enable them with:

```yaml
kyverno:
  enabled: true
  scaling:
    enabled: true
```

Policies render into the release namespace (`metadata.namespace: <Release.Namespace>`) and, being namespaced Kyverno policies, apply to **all** matching resources in that namespace — not only the resources created by this release. Each policy sets `failurePolicy: Fail` and targets one resource type: Knative Services (`serving.knative.dev/v1` — scaling annotations, `containerConcurrency`, `timeoutSeconds`), CNPG Clusters (`postgresql.cnpg.io/v1` — `spec.instances` 1–16), and Dragonfly instances (`dragonflydb.io/v1alpha1` — `spec.replicas` 1–16 and PDB bounds).

`validationActions` controls enforcement: `Deny` (default) blocks non-compliant requests; `Audit` only records them. The policy `apiVersion` defaults to `policies.kyverno.io/v1beta1` (Kyverno >= 1.16); set it to `policies.kyverno.io/v1` on Kyverno >= 1.17.

| Key | Description | Default |
|-----|-------------|---------|
| `kyverno.enabled` | Render the Kyverno admission policies | `false` |
| `kyverno.scaling.enabled` | Render the scaling/HA guardrail policies | `false` |
| `kyverno.scaling.apiVersion` | Policy `apiVersion` (`policies.kyverno.io/v1beta1` or `policies.kyverno.io/v1`) | `policies.kyverno.io/v1beta1` |
| `kyverno.scaling.validationActions` | Enforcement actions (`Deny` and/or `Audit`) | `[Deny]` |

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
*   **dragonfly-cache** — Knative service with DragonflyDB caching, auth, TLS, and snapshots.

## CI/CD

The repository uses GitHub Actions for automated quality assurance:

*   **Lint and Test**: Runs `helm lint`, validates `values.yaml` against a JSON schema, renders templates for all examples, and executes unit tests. It also runs a PR-level Kyverno policy gate that renders the opt-in admission policies and checks the `test/kyverno/` fixtures with the Kyverno CLI.
*   **Release**: Triggers when a chart's `Chart.yaml` version changes on `main` (diff-detected on each push), packaging and pushing that chart to GHCR as an OCI artifact and tagging it `<chart>-v<version>` (for example `ksvc-v0.7.0`). Pushing a matching `<chart>-v<version>` tag also triggers a release.
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
5.  Run `helm lint` and `helm unittest` before submitting changes.
