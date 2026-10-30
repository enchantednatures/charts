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
| `examples/` | Runnable reference configurations: `minimal`, `full-stack`, `postgres-only`, `kafka-consumer`, `kafka-broker`, `kafka-source-net`, `kafka-strimzi`, `kafka-redpanda`, `dragonfly-cache`, `longrunning-websocket`. |
| `test/` | Shared test fixtures (currently the Kyverno guardrail fixtures under `test/kyverno/`). |
| `flux/` | Self-referential Flux GitOps bootstrap that syncs this repo into a cluster — see [flux/README.md](flux/README.md). |
| `hack/` | Repo automation scripts: the PR version gate, local app-chart resolution, and schema, Kubernetes-version, requirements-docs, and Markdown-link checks. |
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

## Requirements

The charts render custom resources; the matching operators must already run in
the cluster. Most `make install-*` targets install **CRDs only** — enough for
`helm template` and server-side dry-runs, but not for reconciliation
(`install-kyverno` is the exception and installs the controller via Helm). Use
the real operators for an actual install. Managed Kafka (`kafka.cluster.enabled`)
needs Strimzi >= 1.0 on Kubernetes >= 1.32, or the Redpanda operator >= 26.2;
Redpanda TLS also requires cert-manager. `make install-strimzi-crds` and
`make install-redpanda-crds` install CRDs only; `hack/install-strimzi-operator.sh`
and `hack/install-redpanda-operator.sh` install the operators for Kind e2e.

| Requirement | Needed for | Notes |
|-------------|------------|-------|
| Kubernetes >= 1.28 | Everything | `kubeVersion` in the library, app, and example charts. |
| [Knative Serving](https://knative.dev/docs/serving/) | `services` (default `workload.type: Knative`) | Includes a networking layer (Kourier, Istio, Contour, …). Deployment-mode services do not need Knative. |
| [Knative Eventing](https://knative.dev/docs/eventing/) | `pingsources`, `kafka.broker`, `kafka.triggers` | Provides the `PingSource`, `Broker`, and `Trigger` CRs and their controllers. |
| [Knative Eventing Kafka](https://github.com/knative-extensions/eventing-kafka-broker) | `kafka.sources`, `kafka.broker` | Provides the `KafkaSource` CR, the Kafka Broker implementation, and their controllers. |
| A Kafka cluster: [Strimzi](https://strimzi.io/) **or** [Redpanda](https://docs.redpanda.com/current/deploy/redpanda/kubernetes/) operator | `kafka.sources`, `kafka.cluster` | The chart renders `KafkaSource` and, when `kafka.cluster.enabled: true`, a managed Strimzi (`Kafka`, `KafkaNodePool`, `KafkaTopic`, `KafkaUser`) or Redpanda (`Redpanda`, `Topic`, `User`) cluster plus a per-release `ConfigMap` for the Broker. The default `bootstrapServers` (`kafka.kafka.svc.cluster.local:9092`) matches a Strimzi `Kafka` named `kafka` in namespace `kafka`; with Redpanda, point `bootstrapServers` at its seed service. Topics must exist unless managed topic creation is enabled. |
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

## Release process

Charts are published to **GHCR as OCI artifacts** at
`oci://ghcr.io/enchantednatures/charts`.

1.  **Feature PR** — changes a chart's source (`templates/`, `values.yaml`, …)
    and bumps that chart's `version:` in `Chart.yaml`. The `version-check` CI
    job (`hack/check-version-bump.sh`) **fails the PR** if a chart changed
    without a version bump.
2.  **Merge to `main`** — `release.yaml` diff-detects charts whose `Chart.yaml`
    `version:` changed on the push, packages them, pushes them to GHCR, tags the
    commit, and creates a GitHub Release. Pushing a tag of the form
    **`<chart>-v<version>`** (for example `ksvc-v0.10.0`) also triggers a release.
3.  **Dependent bump** — when a **library** chart is released, the
    `update-dependents` job opens a PR that bumps the library dependency (and the
    dependent app chart's patch version) and refreshes its `Chart.lock`.

Consumers reference a published chart by OCI repository and version:

```yaml
dependencies:
  - name: ksvc
    version: 0.10.0
    repository: oci://ghcr.io/enchantednatures/charts
```

### Version and lock hygiene

*   The committed `Chart.lock` files for `charts/library/ksvc/test-chart` and
    each `examples/*/` pin the local library (`file://`) version, so a library
    version bump requires refreshing them — run `make update-locks`.
*   `hack/lint-app.sh` resolves `charts/app/ksvc` against the **local** library
    chart for lint/render without touching the committed OCI lock.

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
make docs                 # regenerate charts/library/ksvc/README.md (helm-docs, docker)
make update-locks         # refresh committed Chart.lock files
make template EXAMPLE=minimal

make create-kind-cluster  # Kind cluster + all CRDs
make install-local EXAMPLE=minimal
make install-flux-sync    # apply the flux/ GitOps bootstrap
```

## CI / CD

*   **Lint and Test** (`.github/workflows/lint-test.yaml`) — `make lint`,
    `make test`, positive and negative schema validation, Kubernetes-version
    enforcement, template rendering, kubeconform validation, Kyverno policy
    tests, and the PR chart-version gate.
*   **Docs** (`.github/workflows/docs.yaml`) — helm-docs sync, README
    requirements drift checks, Markdown lint, local link checks, and external
    link checks (also run weekly).
*   **Integration Test** (`.github/workflows/integration-test.yaml`) — nightly
    and PR Kind-cluster dry-runs for every example, a Kyverno guardrails
    end-to-end test, and a Strimzi Kafka end-to-end test.
*   **Release** (`.github/workflows/release.yaml`) — the OCI release pipeline
    described above.

## License

See the [LICENSE](LICENSE) file for the license governing this repository.
