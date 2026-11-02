# ksvc Helm charts

A small collection of Helm charts for running **serverless services on
Knative** with optional CloudNativePG PostgreSQL, Kafka event sources,
DragonflyDB caches, Flagger canaries, Ceph RGW object buckets, and Kyverno
guardrails.

The centrepiece is `ksvc`, a **library chart**: consumers declare one or more
services in a `services:` map and the library renders the Knative Services and
all supporting infrastructure. A ready-to-use application wrapper
(`ksvc-app`) is included for consumers who want to tweak a normal chart.

## Repository layout

| Path | Description |
|------|-------------|
| `charts/library/ksvc/` | The `ksvc` **library chart** — the templates and values that do all the work. See its [README](charts/library/ksvc/README.md) for the full values reference. |
| `charts/app/ksvc/` | `ksvc-app`, a thin **application chart** wrapper that depends on `ksvc` and is a starting point for consumers. |
| [`MIGRATION.md`](MIGRATION.md) | Upgrade guide from `ksvc` 0.5.0 to 1.0.0, with before/after values for every breaking change. |
| `examples/` | Runnable reference configurations: `minimal`, `full-stack`, `postgres-only`, `kafka-consumer`, `kafka-broker`, `kafka-source-net`, `kafka-strimzi`, `kafka-redpanda`, `dragonfly-cache`, `longrunning-websocket`. |
| `test/` | Shared test fixtures (currently the Kyverno guardrail fixtures under `test/kyverno/`). |
| `flux/` | Self-referential Flux GitOps bootstrap that syncs this repo into a cluster — see [flux/README.md](flux/README.md). |
| `hack/` | Repo automation scripts: the PR version gate, local app-chart resolution, release gating and reconciliation, lock consistency, and schema, Kubernetes-version, requirements-docs, and Markdown-link checks. |
| `.github/workflows/` | CI/CD workflows (see [CI](#ci--cd)). |

## The charts

*   **[ksvc library chart](charts/library/ksvc/README.md)** — Knative Services
    (plus opt-in standard Deployments for long-running services), CloudNativePG,
    Kafka sources + DLQ, DragonflyDB, Flagger canaries, Ceph RGW object buckets,
    Kyverno admission policies. Its README is generated from `values.yaml` by
    [helm-docs](https://github.com/norwoodj/helm-docs) (`make docs`).
*   **ksvc-app application chart** (`charts/app/ksvc/`) — wraps `ksvc` so that
    consumers can `helm install` a normal chart. Pins a `ksvc` version via an
    `oci://ghcr.io/enchantednatures/charts` dependency.

Upgrading from `ksvc` 0.5.0? Read the [migration guide](MIGRATION.md) for the
multi-service move, the 0.7-0.10 feature additions, and the 1.0.0 API freeze,
including before/after values for every breaking change.

## Requirements

Helm **3.17+** and **4.x** are supported; CI runs both a Helm 3.17 lane and a
Helm 4.3.0 lane.

The charts render custom resources; the matching operators must already run in
the cluster. Most `make install-*` targets install **CRDs only** — enough for
`helm template` and server-side dry-runs, but not for reconciliation
(`install-kyverno` is the exception and installs the controller via Helm). Use
the real operators for an actual install. Managed Kafka (`kafka.cluster.enabled`)
needs Strimzi >= 1.0 on Kubernetes >= 1.32, or the Redpanda operator >= 26.2;
Redpanda TLS also requires cert-manager. `make install-strimzi-crds` and
`make install-redpanda-crds` install CRDs only; `hack/install-strimzi-operator.sh`
and `hack/install-redpanda-operator.sh` install the operators for Kind e2e.
`hack/install-kafka-source-controller.sh` installs the KafkaSource controller
and conversion webhook for the Strimzi e2e (the `make install-kafka` target
installs only the KafkaSource CRD). `hack/install-eventing-core.sh` installs
the Knative Eventing core that the KafkaSource controller and webhook require.

| Requirement | Needed for | Notes |
|-------------|------------|-------|
| [Helm](https://helm.sh/) 3.17+ (3.x) or 4.x | Everything | CI runs a Helm 3.17 lane and a Helm 4.3.0 lane. |
| Kubernetes >= 1.28 | Everything | `kubeVersion` in the library, app, and example charts. |
| [Knative Serving](https://knative.dev/docs/serving/) | `services` (default `workload.type: Knative`) | Includes a networking layer (Kourier, Istio, Contour, …). Deployment-mode services do not need Knative. |
| [Knative Eventing](https://knative.dev/docs/eventing/) | `pingsources`, `kafka.broker`, `kafka.triggers` | Provides the `PingSource`, `Broker`, and `Trigger` CRs and their controllers. |
| [Knative Eventing Kafka](https://github.com/knative-extensions/eventing-kafka-broker) | `kafka.sources`, `kafka.broker` | Provides the `KafkaSource` CR, the Kafka Broker implementation, and their controllers. |
| A Kafka cluster: [Strimzi](https://strimzi.io/) **or** [Redpanda](https://docs.redpanda.com/current/deploy/redpanda/kubernetes/) operator | `kafka.sources`, `kafka.cluster` | The chart renders `KafkaSource` and, when `kafka.cluster.enabled: true`, a managed Strimzi (`Kafka`, `KafkaNodePool`, `KafkaTopic`, `KafkaUser`) or Redpanda (`Redpanda`, `Topic`, `User`) cluster plus a per-release `ConfigMap` for the Broker. The default `bootstrapServers` (`kafka.kafka.svc.cluster.local:9092`) matches a Strimzi `Kafka` named `kafka` in namespace `kafka`; with an external Redpanda cluster, point `bootstrapServers` at its seed service. Topics must exist unless managed topic creation is enabled. |
| [CloudNativePG](https://cloudnative-pg.io/) operator | `postgres.enabled` | Provides `Cluster`, `Pooler`, `ScheduledBackup`. Also requires a `ClusterImageCatalog` named `postgresql` containing the requested major version (the chart default); apply one from the [CloudNativePG catalogs](https://github.com/cloudnative-pg/artifacts/tree/main/image-catalogs) or override `postgres.imageCatalog.name`. |
| [Barman Cloud plugin](https://github.com/cloudnative-pg/plugin-barman-cloud) | `postgres.backup.enabled` | Provides the `ObjectStore` CR (`barmancloud.cnpg.io/v1`) used for S3 backups and WAL archiving. |
| [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) CRDs | `postgres.monitoring.enabled` (default `true` when Postgres is enabled) | Renders `PodMonitor` and `PrometheusRule`. Disable monitoring if the CRDs are absent. A Prometheus instance is also required by Flagger. |
| [Dragonfly Operator](https://github.com/dragonflydb/dragonfly-operator) | `dragonfly.enabled` | Provides the `Dragonfly` CR (`dragonflydb.io/v1alpha1`). |
| [Flagger](https://flagger.app/) | `services.<key>.flagger.enabled` | Renders `Canary`; must be configured with the Knative provider and a metrics provider. Defaults assume Prometheus at `prometheus.observability.svc.cluster.local:9090` and the k6 load tester at `k6-loadtester.flagger-system` (load tests can be disabled). |
| [Rook-Ceph](https://rook.io/) (CephObjectStore + RGW) and the [lib-bucket-provisioner](https://github.com/kube-object-storage/lib-bucket-provisioner) CRDs | `objectBuckets` | The chart renders `ObjectBucketClaim` only. Requires an existing bucket `StorageClass` (for example `provisioner: rook-ceph.ceph.rook.io/bucket`) and a reachable RGW endpoint. |
| [cert-manager](https://cert-manager.io/) | `postgres.certManager.enabled`, `dragonfly.tls.certManager.enabled` | Optional; renders `Certificate` resources. Without it, supply the TLS Secrets yourself. |
| [Kyverno](https://kyverno.io/) >= 1.16 | `kyverno.enabled` | Optional admission guardrails (`NamespacedValidatingPolicy`). Use `policies.kyverno.io/v1` on Kyverno >= 1.17. |
| A default StorageClass (or an explicit `storageClassName`) | `postgres.enabled`, `dragonfly.snapshot` | PVCs for Postgres instance volumes and Dragonfly snapshots. |

The versions exercised by CI are pinned at the top of the [`Makefile`](Makefile)
(Knative Serving/Eventing v1.17.0, CNPG release-1.25, eventing-kafka v1.17.0,
Kyverno 3.9.1, Strimzi 1.3.0, Redpanda operator 26.2.5). Managed Strimzi
requires Kubernetes >= 1.32; the Strimzi e2e job pins a Kind 1.32 node image.

### Compatibility matrix

This matrix targets the `ksvc` and `ksvc-app` **1.0.0** line. Both charts expose
the same values surface; `ksvc-app` pins the matching `ksvc` release.

| Component | CI-tested / pinned | Supported | Notes |
|-----------|-------------------|-----------|-------|
| Kubernetes | 1.28.0, 1.30.0, 1.32.0 (kubeconform); 1.32.0 Kind e2e | >= 1.28 | Every chart declares `kubeVersion: ">=1.28.0"`. Managed Strimzi needs >= 1.32. |
| Helm | 3.17.0 and 4.3.0 | >= 3.17 (3.x) and 4.x | CI runs both lanes; 3.17.0 is the minimum. OCI installs require >= 3.8, but the chart is tested from 3.17. |
| Knative Serving | v1.17.0 | `serving.knative.dev/v1` | Required for default `workload.type: Knative`; Deployment-mode services do not need it. |
| Knative Eventing | v1.17.0 | `eventing.knative.dev/v1` | Required for `pingsources`, `kafka.broker`, and `kafka.triggers`. |
| eventing-kafka | v1.17.0 | `sources.knative.dev/v1beta1` (KafkaSource) | Required for `kafka.sources` and the Kafka Broker implementation. |
| CloudNativePG | release-1.25 | `postgresql.cnpg.io/v1` | Requires a `ClusterImageCatalog` named `postgresql` (chart default) or an override. |
| Barman Cloud plugin | v0.15.1 | `barmancloud.cnpg.io/v1` | Only for `postgres.backup.enabled`; renders the `ObjectStore` CR. |
| Dragonfly operator | v1.7.1 | `dragonflydb.io/v1alpha1` | Renders the `Dragonfly` CR. |
| Flagger | v1.45.0 | `flagger.app/v1beta1` | Knative provider; Prometheus and the k6 load tester are configured on the Flagger installation. |
| Kyverno | 3.9.1 chart; 1.19.1 CLI | >= 1.16 | `policies.kyverno.io/v1beta1` on Kyverno 1.16, `policies.kyverno.io/v1` on >= 1.17. |
| Prometheus Operator | v0.94.2 | `monitoring.coreos.com/v1` | Renders `PodMonitor` and `PrometheusRule`; a Prometheus instance is also required by Flagger. |
| Strimzi | 1.3.0 | `kafka.strimzi.io/v1` | Managed Kafka only; requires Kubernetes >= 1.32. |
| Redpanda operator | 26.2.5 | `cluster.redpanda.com/v1alpha2` | Managed Kafka only; TLS requires cert-manager. |
| lib-bucket-provisioner | commit `be094b8c7ee9aa948aeaaa7ff6ee6e5f359393ad` (master) | `objectbucket.io/v1alpha1` | The only release tag (`kubernetes-v1.14.1`) ships an `apiextensions.k8s.io/v1beta1` CRD, which Kubernetes >= 1.22 no longer serves. The Makefile therefore pins the master commit that renders `apiextensions.k8s.io/v1`. |

### Rendered CRD API versions

| API version | Resources |
|-------------|-----------|
| `serving.knative.dev/v1` | Knative Service |
| `sources.knative.dev/v1beta1` | KafkaSource |
| `sources.knative.dev/v1` | PingSource |
| `eventing.knative.dev/v1` | Broker, Trigger |
| `postgresql.cnpg.io/v1` | Cluster, Pooler, ScheduledBackup |
| `barmancloud.cnpg.io/v1` | ObjectStore |
| `monitoring.coreos.com/v1` | PodMonitor, PrometheusRule |
| `dragonflydb.io/v1alpha1` | Dragonfly |
| `flagger.app/v1beta1` | Canary |
| `objectbucket.io/v1alpha1` | ObjectBucketClaim |
| `kafka.strimzi.io/v1` | Kafka, KafkaNodePool, KafkaTopic, KafkaUser |
| `cluster.redpanda.com/v1alpha2` | Redpanda, Topic, User |
| `policies.kyverno.io/v1beta1` or `policies.kyverno.io/v1` | NamespacedValidatingPolicy (configurable via `kyverno.scaling.apiVersion`) |
| `cert-manager.io/v1` | Certificate |
| `apps/v1` | Deployment (Deployment workload) |
| `policy/v1` | PodDisruptionBudget (Deployment workload) |

## Release process

Charts are published to **GHCR as OCI artifacts** at
`oci://ghcr.io/enchantednatures/charts`.

1.  **Feature PR** — changes a chart's source (`templates/`, `values.yaml`, …)
    and bumps that chart's `version:` in `Chart.yaml`. The `version-check` CI
    job (`hack/check-version-bump.sh`) **fails the PR** if a chart changed
    without a version bump.
2.  **Merge to `main`** — `release.yaml` diff-detects charts whose `Chart.yaml`
    `version:` changed on the push. Before packaging, a `gate` job waits for the
    release commit's required checks and fails closed if any are missing, failed,
    or still pending after its bounded poll. The gate covers `Helm Lint`,
    `Schema Validation`, `Template Rendering`, `Helm Unit Tests`,
    `Kubernetes Schema Validation`, every `Kind Cluster Deploy (…)` matrix lane,
    `App Chart Dry-Run`, `Kyverno Guardrails E2E`, and `Kafka Strimzi E2E`.
    Pushing a tag of the form **`<chart>-v<version>`** (for example
    `ksvc-v1.0.0`) also triggers a release and is gated against that tag's
    commit.
3.  **Independent reconciliation** — the release job checks the OCI artifact,
    the git tag, and the GitHub Release separately. Existing artifacts are never
    overwritten; a missing OCI artifact, tag, or Release is created. If the tag
    already exists it must point at the expected release commit (the commit that
    produced the chart version); a tag at any other commit fails with a clear
    error instead of being moved or reused.
4.  **Dependent bump** — when a **library** chart is released, the
    `update-dependents` job opens a PR that bumps the library dependency (and the
    dependent app chart's patch version) and refreshes its `Chart.lock`.

### Release repair and dispatch

`release.yaml` also accepts `workflow_dispatch` for an explicit chart/version and
repair runs:

| Input | Description |
|-------|-------------|
| `chart` | Chart name to release, for example `ksvc` or `ksvc-app` (required). |
| `version` | Version to release; must match that chart's `Chart.yaml` (required). |
| `repair` | When `true`, only repair a missing tag or GitHub Release for a version whose OCI artifact already exists. Repair never publishes a new chart version. |
| `commit` | Commit that produced the chart version. When omitted, the workflow derives the commit that introduced that `Chart.yaml` version from git history. |

A dispatch never falls back to `HEAD~1`: the expected release commit is either
the explicit `commit` input or a commit derived from the chart's version history,
and the workflow fails if neither can be established.

The publish job declares `environment: release`. Required reviewers, wait timers,
and deployment branch rules for that environment are repository settings, not
workflow code; they must be configured externally for the environment reference
to enforce them.

Consumers reference a published chart by OCI repository and version:

```yaml
dependencies:
  - name: ksvc
    version: 1.0.0
    repository: oci://ghcr.io/enchantednatures/charts
```

### Version and lock hygiene

*   The committed `Chart.lock` files for `charts/app/ksvc`,
    `charts/library/ksvc/test-chart`, and each `examples/*/` chart pin their
    dependencies, so a dependency version bump requires refreshing them — run
    `make update-locks`.
*   The **Chart Lock Consistency** CI job runs `helm dependency build` for the
    app chart, the test-chart, and every example against the committed lock. It
    fails if a lock is stale or if a build rewrites it. Run `make check-locks`
    locally.
*   `hack/lint-app.sh` verifies the committed app lock against `Chart.yaml`
    before rewriting it to the local library for lint/render, so the local
    rewrite cannot mask lock drift. `hack/lint-app.sh --check-lock` runs only
    that verification.

## Local development

Requires `helm`, `kubectl`, `kind`, and `docker` (for `make docs`).

```bash
make help                 # list every target

make lint                 # helm lint library + app + all examples
make test                 # helm-unittest suite
make test-schema          # values.schema.json positive + negative cases
make test-kube-version    # examples/app reject Kubernetes < 1.28
make check-docs           # README requirements drift check
make check-markdown-links # local Markdown link check
make check-locks          # committed Chart.lock files match Chart.yaml
make test-release-logic   # release gate, reconciliation, and lock tests
make docs                 # regenerate charts/library/ksvc/README.md (helm-docs, docker)
make update-locks         # refresh committed Chart.lock files
make template EXAMPLE=minimal

make create-kind-cluster  # Kind cluster + all CRDs
make install-local EXAMPLE=minimal
make install-flux-sync    # apply the flux/ GitOps bootstrap
```

## CI / CD

*   **Lint and Test** (`.github/workflows/lint-test.yaml`) — Helm 3.17 and
    Helm 4.3.0 lanes for `make lint`, `make test`, template rendering, and
    kubeconform; positive and negative schema validation, Kubernetes-version
    enforcement, Kyverno policy tests, and the PR chart-version gate. Helm
    unit tests use helm-unittest 0.8.2 on Helm 3.17 and 1.0.3 on Helm 4.
    kubeconform is fail-closed against Kubernetes 1.28, 1.30, and 1.32 using
    the Datree CRD catalog plus a vendored KafkaSource schema. The same
    workflow runs the Chart Lock Consistency job and the Release Logic Tests
    (release gate, reconciliation, and stale-lock fixtures).
*   **Docs** (`.github/workflows/docs.yaml`) — helm-docs sync, README
    requirements drift checks, Markdown lint, local link checks, and external
    link checks (also run weekly).
*   **Integration Test** (`.github/workflows/integration-test.yaml`) — nightly
    and PR Kind-cluster dry-runs for every example, a real Helm 4 install
    smoke test, a Kyverno guardrails end-to-end test, and a Strimzi Kafka
    end-to-end test.
*   **Release** (`.github/workflows/release.yaml`) — the gated, independently
    reconciled OCI release pipeline described above.

## Contributing and support

*   **Contributing:** read [CONTRIBUTING.md](CONTRIBUTING.md) for local test
    commands, pull request expectations, and conventional commit style.
*   **Versioning and deprecation:** the public values API follows SemVer. See
    [the versioning and deprecation policy](CONTRIBUTING.md#versioning-and-deprecation)
    for major, minor, and patch rules, experimental features, and the required
    breaking-change release-note format.
*   **Support:** open a GitHub issue using the bug report or feature request
    template. Security reports go through [SECURITY.md](SECURITY.md).
*   **Security:** report vulnerabilities privately through GitHub Security
    Advisories as described in [SECURITY.md](SECURITY.md).
*   **Code of conduct:** participation is covered by
    [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

See the [LICENSE](LICENSE) file for the license governing this repository.
