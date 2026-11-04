# Changelog

All notable changes to the `ksvc` and `ksvc-app` charts are recorded here. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file tracks the product lines behind the charts. Exact chart patch and
prerelease versions (for example `ksvc` `1.0.0-rc.1.4` and `ksvc-app` `0.7.5`)
are documented by the generated GitHub Release notes attached to each published
OCI artifact, so a patch or prerelease does not need its own entry here. The
`1.0.0` section below covers every chart that targets the `1.0.0` values API.

## [1.2.1] - 2026-11-04

### Fixed

- Label `ObjectBucketClaim`s with `bucket-notification-<notification-name>` so
  Rook applies the referenced `CephBucketNotification`. The previous
  `bucket-notification-<event>` key did not match Rook's label contract and
  notifications were silently ignored.

## [1.2.0] - 2026-11-03

### Added

- `global.clusterDomain` (default `cluster.local`) controls generated managed
  Kafka bootstrap addresses, Flagger k6 service URLs, and certificate SANs.
- `flagger.loadTester.*` defines the load-tester namespace/service/scheme/port/
  path; `services.<key>.flagger.loadTest.webhookUrl` now defaults to an empty
  string and derives its value from it. New `smokePath`, `path`, `smokeTimeout`,
  and `timeout` fields cover the generated k6 webhooks.
- `kafka.bootstrapServers` sets the default bootstrap list for KafkaSources and
  the Broker. `kafka.cluster.listeners.plainPort`/`tlsPort` configure managed
  Kafka listener ports.
- `postgres.monitoring.podMonitor.*` and `postgres.monitoring.prometheusRule.*`
  expose discovery labels, scrape interval/timeout, path, scheme, and rule
  evaluation interval.
- Kafka source and trigger DLQs accept `dlq.port` and `dlq.env`.
- `services.<key>.objectBuckets` binds an `objectBuckets` entry to an app via
  `envFrom` or individual named environment variables. The claim Secret and
  ConfigMap names can be overridden.
- **Experimental:** `objectBuckets.<key>.notifications` publishes Ceph RGW
  bucket events to the chart-managed Kafka cluster. Events are opt-in per key
  (`put`, `post`, `copy`, `multipart`, `delete`, `delete-marker`) and create a
  `CephBucketTopic`, `CephBucketNotification`, and Kafka topic. The current
  release supports the plaintext, unauthenticated managed listener only;
  authenticated/TLS notifications are tracked in issue #137.

### Changed

- The default `prometheus.io/port` annotation follows
  `services.<key>.port` unless the annotation is set explicitly.

## [1.0.0] - 2026-11-02

The first stable release of the multi-service library. Consumers moving from
`0.5.0` should follow the [migration guide](MIGRATION.md), which documents every
breaking change with before/after values.

### Added

- The `services` map renders one Knative Service per key, or an `apps/v1`
  Deployment plus `Service` and optional PodDisruptionBudget when
  `services.<key>.workload.type: Deployment`. Each service can enable its own
  Flagger canary, autoscaling, annotations, and resource settings.
- Managed Kafka clusters on Strimzi or Redpanda, Knative Broker and Trigger
  eventing, KafkaSource delivery with retries and a dead-letter handler, and
  PingSource scheduled events.
- CloudNativePG PostgreSQL clusters with poolers, scheduled backups, Prometheus
  monitoring, and Ceph RGW `ObjectBucketClaim` wiring for backups and Dragonfly
  snapshots.
- DragonflyDB cache clusters with optional persistence, Kyverno admission
  guardrails, and Kyverno scaling policies.
- `ksvc-app`, a thin application chart that exposes the `ksvc` values surface
  through a normal Helm dependency.
- A JSON schema for `values.yaml`, schema positive/negative tests, and CI
  coverage across Helm 3.17 and 4.x and Kubernetes 1.28, 1.30, and 1.32.
- Signed OCI releases with cosign keyless signatures, Syft SBOMs, and SLSA
  provenance, plus a documented verification procedure in
  [RELEASING.md](RELEASING.md).

### Changed

- The values API is frozen for the 1.0 line. `ksvc-app` exposes the same values
  as the library, and `stability` is no longer an experimental surface.
- Release automation now gates on required checks, reconciles the OCI artifact,
  git tag, and GitHub Release independently, and repairs missing metadata
  without republishing an existing version.
- Default PostgreSQL statement logging was removed in 0.7.3; `postInitSQL` now
  only enables `pg_stat_statements` by default.
- `global.nameOverride` now sets `app.kubernetes.io/name` on release-wide
  resources, while resource names still derive from `global.fullnameOverride`
  or the release name.
- `bucketRef` derives backup and snapshot destination paths, endpoints, and
  credentials unless the consumer sets an explicit value.

### Removed

- `services.<key>.flagger.metrics.prometheusAddress` was removed from the
  values schema and loader; Flagger's metrics provider is configured on the
  Flagger installation instead.
- `kafka.sources.<key>.topic` is no longer required and defaults to `events`.
- The pre-0.5.0 top-level `knativeService`, `flagger`, and `kafka` layouts are
  no longer supported.

### Fixed

- Deployment-mode services no longer share selectors with Knative Services, and
  immutable selector changes are documented as requiring resource recreation.
- `objectBuckets` keys are capped at 53 characters so the generated claim name
  never truncates at the Kubernetes 63-character limit.
- The chart no longer validates `maxUnavailable` against the replica count; the
  behavior is documented as intentional for percentage and integer inputs.

[1.2.0]: https://github.com/enchantednatures/charts/releases/tag/ksvc-v1.2.0
[1.0.0]: https://github.com/enchantednatures/charts/releases/tag/ksvc-v1.0.0
