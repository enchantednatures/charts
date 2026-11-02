# Migrating ksvc from 0.5.0 to 1.0.0

This guide covers the breaking and behavior-changing values changes between the
multi-service `v0.5.0` tag and the `1.0.0` release. It is written for consumers
of the `ksvc` **library** chart; the `ksvc-app` 1.0.0 wrapper exposes the same
values surface.

Every "After" example is rendered with `helm template` against the local chart
source. "Before" examples target the release named in the section and are kept
to show the exact shape being replaced.

## Upgrade checklist

| Release | Change | Action |
|---------|--------|--------|
| `0.5.0` | Multi-service layout | Move `knativeService.*` to `services.<key>.*`, top-level `flagger.*` to `services.<key>.flagger.*`, and top-level `kafka.*` to `kafka.sources.<key>.*`. |
| `0.7.0` | Object buckets | Add `objectBuckets` and point `postgres.backup.objectStore.bucketRef` or `dragonfly.snapshot.bucketRef` at an entry. |
| `0.7.3` | Statement logging defaults | Remove `log_statement` / `log_min_duration_statement` from `postInitSQL` unless you explicitly want them. |
| `0.8.0` | Deployment workload | Use `services.<key>.workload.type: Deployment` for long-lived connections. Expect resource recreation if the selector identity changes. |
| `0.9.0` | PingSource | Add `pingsources.<key>` entries; no change for existing services. |
| `0.10.0` | Managed Kafka and eventing | Optionally enable `kafka.cluster`, `kafka.broker` / `kafka.triggers`, and `kafka.sources.<key>.net`. |
| `1.0.0` | API freeze | Remove `services.<key>.flagger.metrics.prometheusAddress`; `kafka.sources.<key>.topic` is optional; review `global.nameOverride`; review `objectBuckets` key lengths and `bucketRef` defaults. |

## 0.5.0: multi-service values layout

The `v0.5.0` tag moved from a single top-level `knativeService` plus top-level
`flagger` and `kafka` blocks to keyed maps. The old layout renders a resource
named after the release; the new layout names each service resource after its
service key (`<release>-<key>`). KafkaSource and DLQ resources use the
`kafka.sources` key instead.

Before (`v0.4.0` and earlier):

```yaml
knativeService:
  image:
    repository: ghcr.io/org/my-app
    tag: v1.0.0

flagger:
  enabled: true

kafka:
  enabled: true
  source:
    topic: my-events
```

After (`0.5.0` and later):

```yaml
services:
  app:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0
    flagger:
      enabled: true

kafka:
  sources:
    events:
      topic: my-events
      sink: app
```

Notes:

*   `services` is a map keyed by a consumer-chosen service name. Each key is
    the name suffix for the Knative Service, Deployment, Flagger Canary, and
    related per-service resources. KafkaSource and DLQ names use the
    `kafka.sources` key instead.
*   `kafka.enabled` is gone. A `kafka.sources` entry is what enables a source.
*   `kafka.source.sink` was implicit in the old layout (the single Knative
    Service). In the map layout each source must set `sink` to a key in
    `services`, unless `kafka.broker.enabled` is true.
*   Per-source `delivery` and `dlq` moved under each `kafka.sources.<key>`
    entry; `kafka.dlq.enabled` is now `kafka.sources.<key>.dlq.enabled`.

## 0.7.0: objectBuckets and bucketRef

`0.7.0` added `objectBuckets`, which renders one `ObjectBucketClaim` per entry,
and `bucketRef` wiring for PostgreSQL backups and Dragonfly snapshots. Before
this release, S3 credentials and endpoints were hand-written in the backup and
snapshot blocks.

Before (`0.6.x`):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

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

After (`0.7.0` and later):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

objectBuckets:
  postgres-backups:
    storageClassName: ceph-bucket
    endpointURL: http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80

postgres:
  enabled: true
  backup:
    enabled: true
    objectStore:
      bucketRef: postgres-backups
```

Dragonfly uses the same bucket map with `dragonfly.snapshot.bucketRef`:

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

objectBuckets:
  dragonfly-snapshots:
    storageClassName: ceph-bucket
    endpointURL: http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80
    region: us-east-1

dragonfly:
  enabled: true
  snapshot:
    enabled: true
    bucketRef: dragonfly-snapshots
```

Each `bucketRef` derives the S3 destination, endpoint, and credentials from the
referenced bucket. Explicit values still win; see [bucketRef defaults](#bucketref-defaults).

## 0.7.3: statement logging removed from defaults

`ksvc-v0.7.3` removed `ALTER SYSTEM SET log_statement` and
`ALTER SYSTEM SET log_min_duration_statement` from the default `postInitSQL`.
The default now only creates `pg_stat_statements`. This avoids writing every
statement, including credentials and PII, to the PostgreSQL logs.

Before (`0.7.2` default):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

postgres:
  enabled: true
  backup:
    enabled: false
  postInitSQL:
    - "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
    - "ALTER SYSTEM SET log_statement = 'all';"
    - "ALTER SYSTEM SET log_min_duration_statement = '1000';"
```

After (`0.7.3` and later default):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

postgres:
  enabled: true
  backup:
    enabled: false
  postInitSQL:
    - "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

If you deliberately need statement logging, keep the `ALTER SYSTEM` entries in
`postInitSQL` yourself. If you relied on the old default without declaring it,
the setting silently disappears after the upgrade.

## 0.8.0: Deployment workload

`0.8.0` added `services.<key>.workload.type: Deployment`. Knative remains the
default. Deployment mode renders an `apps/v1` Deployment, a core `v1` Service,
and an optional `policy/v1` PodDisruptionBudget instead of a Knative Service.

Before (`0.7.x`, Knative only):

```yaml
services:
  gateway:
    image:
      repository: ghcr.io/org/websocket-gateway
      tag: v1.0.0
```

After (`0.8.0` and later, Deployment mode):

```yaml
services:
  gateway:
    image:
      repository: ghcr.io/org/websocket-gateway
      tag: v1.0.0
    workload:
      type: Deployment
      replicas: 2
    service:
      type: LoadBalancer
      port: 80
```

Caveat: the Deployment's `selector` is immutable. Changing `workload.type`, the
service map key, or `services.<key>.nameOverride` changes the selector identity,
so the old resources are replaced rather than updated in place. Plan for
recreation (and downtime) when making that change on a live release. Flagger is
not supported with `workload.type: Deployment`, and a Kafka source `sink`
cannot reference a Deployment-backed service because a plain Kubernetes
Service is not Knative-addressable.

## 0.9.0: PingSource

`0.9.0` added the `pingsources` map. Each entry renders a
`sources.knative.dev/v1` `PingSource` named `<release>-<key>-ping-source`.
Nothing changes for releases that do not use it.

After (`0.9.0` and later):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

pingsources:
  scheduled:
    schedule: "0 * * * *"
    timezone: "UTC"
    data: '{"hello":"world"}'
    contentType: application/json
    sink: api
```

`sink` must reference a key in `services`. `ceOverrides.extensions` may add or
override extension attributes, but it cannot change the CloudEvent `type`.

## 0.10.0: managed Kafka, Broker/Trigger, and KafkaSource net

`0.10.0` added three independent capabilities: chart-managed Strimzi or
Redpanda clusters, a Knative Kafka Broker with Triggers, and KafkaSource
`net` (TLS/SASL).

### Managed Strimzi

Before (`0.9.x`, external Kafka only):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  sources:
    orders:
      topic: shared-events
      sink: api
      bootstrapServers:
        - kafka.kafka.svc.cluster.local:9092
```

After (`0.10.0` and later, chart-managed Strimzi):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  cluster:
    enabled: true
    provider: strimzi
    replicas: 3
    storage:
      size: 20Gi
    tls:
      enabled: true
    auth:
      type: scram
    topics:
      create: true
  sources:
    orders:
      topic: shared-events
      sink: api
      net:
        tls:
          enabled: true
        sasl:
          enabled: true
```

Strimzi-managed Kafka requires Strimzi `>= 1.0` and Kubernetes `>= 1.32`. When
`kafka.cluster.enabled` is true, do not set explicit `bootstrapServers` on a
source or the Broker; rendering fails instead of silently overriding the
managed endpoint.

### Managed Redpanda

Set `provider: redpanda` instead of `strimzi`:

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  cluster:
    enabled: true
    provider: redpanda
    replicas: 3
    storage:
      size: 20Gi
    tls:
      enabled: false
    auth:
      type: none
    topics:
      create: true
  sources:
    orders:
      topic: shared-events
      sink: api
```

Redpanda requires the Redpanda operator `>= 26.2`. TLS requires cert-manager,
and SCRAM requires `kafka.cluster.redpanda.sasl.secretRef`.

### Kafka Broker and Triggers

Before (`0.9.x`, each source sinks directly to a service):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  sources:
    incoming:
      topic: incoming-events
      sink: api
```

After (`0.10.0` and later, sources sink to the Broker and Triggers fan out):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  broker:
    enabled: true
  sources:
    incoming:
      topic: incoming-events
  triggers:
    all-events:
      subscriber: api
```

With the Broker enabled, a source must not set `sink`; it delivers to the
Broker. Each Trigger requires `subscriber` to be a key in `services`.

### KafkaSource TLS and SASL

Before (`0.9.x`, plaintext KafkaSource):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  sources:
    events:
      topic: incoming-events
      sink: api
      bootstrapServers:
        - kafka.example.svc.cluster.local:9092
```

After (`0.10.0` and later, TLS + SASL):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  sources:
    events:
      topic: incoming-events
      sink: api
      bootstrapServers:
        - kafka.example.svc.cluster.local:9093
      net:
        tls:
          enabled: true
          caCertSecret: kafka-ca
          caCertKey: ca.crt
        sasl:
          enabled: true
          mechanism: SCRAM-SHA-512
          userSecret: kafka-auth
          userKey: user
          passwordSecret: kafka-auth
          passwordKey: password
```

TLS-only is treated by Knative as mTLS, so `certSecret` and `keySecret` are
required in that case. SASL-only renders no TLS block. The chart creates a
`<release>-<key>-kafka-sasl-type` Secret for the mechanism.

## 1.0.0: API freeze

### Removed `flagger.metrics.prometheusAddress`

`services.<key>.flagger.metrics.prometheusAddress` is removed from the values
schema and from the loader defaults. The Canary template never consumed it;
Flagger's metrics provider is configured on the Flagger installation, not in
the `Canary` resource. Remove the key from your values.

Before (`0.10.0`, accepted but unused):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0
    flagger:
      enabled: true
      metrics:
        prometheusAddress: http://prometheus.observability.svc.cluster.local:9090
```

After (`1.0.0`):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0
    flagger:
      enabled: true
```

Helm does not apply a library chart's `values.schema.json` to consumer values,
so an unknown key still renders; it is ignored. Remove it anyway so schema
validation and future upgrades stay clean.

### KafkaSource `topic` is optional

`kafka.sources.<key>.topic` is no longer required in the schema. When omitted,
the source consumes the `events` topic. The loader already defaulted to
`events`; `1.0.0` makes the schema match that behavior.

Before (`0.10.0` schema required `topic`):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  sources:
    events:
      topic: events
      sink: api
```

After (`1.0.0`):

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

kafka:
  sources:
    events:
      sink: api
```

An explicit `topic` always wins. Set it when you do not want the `events`
default.

### `global.nameOverride` controls the release-wide name label

`global.nameOverride` now sets `app.kubernetes.io/name` on release-wide
resources (for example CNPG, Dragonfly, Kafka Broker, ObjectBucketClaim, and
Kyverno resources). Before `1.0.0` it had no effect on those labels; they used
the release fullname. Resource **names** are unchanged and still derive from
`global.fullnameOverride` / the release name.

Values:

```yaml
global:
  nameOverride: my-platform

services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

postgres:
  enabled: true
  backup:
    enabled: false
```

Before (`0.10.0`) rendered label:

```yaml
app.kubernetes.io/name: demo
```

After (`1.0.0`) rendered label:

```yaml
app.kubernetes.io/name: my-platform
```

Per-service resources keep their service label
(`app.kubernetes.io/name: <release>-<key>`), so `global.nameOverride` does not
rename services. If you set it only because older docs suggested it, remove it
unless you want the new label behavior.

### `maxUnavailable > replicas` is intentionally not validated

The chart does not compare `services.<key>.workload.strategy.maxUnavailable`
against `workload.replicas`, and `1.0.0` documents that as intentional. A value
greater than the replica count is legal Kubernetes input: the rollout simply
takes every pod down at once. Percentage strings have no fixed integer value to
compare. The chart validates the PodDisruptionBudget `minAvailable` /
`maxUnavailable` mutual exclusion and that a numeric `minAvailable` does not
exceed replicas; it intentionally does not bound `maxUnavailable`.

This example renders as-is under `1.0.0`:

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0
    workload:
      type: Deployment
      replicas: 1
      strategy:
        maxUnavailable: 5
```

If you need a safety check, enforce it in your own values pipeline; the chart
will not reject it.

### `objectBuckets` keys are limited to 53 characters

`values.schema.json` now caps `objectBuckets` keys at 53 characters in addition
to the DNS-1123 label pattern. The render-time validator has enforced the same
limit since `0.7.0`; `1.0.0` makes the schema agree with it. Use a short,
descriptive key:

```yaml
services:
  api:
    image:
      repository: ghcr.io/org/my-app
      tag: v1.0.0

objectBuckets:
  postgres-backups:
    storageClassName: ceph-bucket
    endpointURL: http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80
```

The generated `ObjectBucketClaim` is `<release>-<key>` and is truncated to the
63-character Kubernetes name limit. The 53-character cap keeps room for the
release prefix and avoids truncation and collision surprises.

### `bucketRef` defaults

When `postgres.backup.objectStore.bucketRef` is set, the chart derives:

*   `destinationPath` -> `s3://<bucketName>/` unless you set it explicitly.
*   `endpointURL` -> the bucket entry's `endpointURL` unless you set it explicitly.
*   `s3Credentials` -> the claim-named Secret with keys `AWS_ACCESS_KEY_ID` and
    `AWS_SECRET_ACCESS_KEY`, unless **any** `s3Credentials` field is set
    explicitly. In that case the whole `s3Credentials` object is treated as
    consumer-owned and nothing is derived.

When `dragonfly.snapshot.bucketRef` is set, the chart derives:

*   `dir` -> `s3://<bucketName>/` unless you set it explicitly.
*   `--s3_endpoint=<host:port>` with the URL scheme stripped.
*   `--s3_use_https=true|false` from the endpoint scheme.
*   `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from the claim-named Secret,
    plus `AWS_REGION` from the bucket entry's `region` when set.

`bucketRef` and `dragonfly.snapshot.existingPersistentVolumeClaimName` are
mutually exclusive. Explicit user-provided `dragonfly.env` entries and
`dragonfly.args` flags are never duplicated.

## Verifying a migration

Render the changed values against the chart version you are upgrading to before
applying them to a cluster:

```bash
helm dependency build ./my-chart
helm template my-release ./my-chart \
  --namespace my-namespace \
  --values values.yaml > /tmp/rendered.yaml
```

Compare the rendered kinds and names with the pre-upgrade output. Pay special
attention to `services.<key>.workload.type` changes (immutable Deployment
selectors), `global.nameOverride` (label changes), and `objectBuckets` (bucket
names are immutable once a claim binds).

The repository's own examples are rendered in CI for every supported Helm and
Kubernetes lane; see [the compatibility matrix](README.md#compatibility-matrix)
for the versions exercised.
