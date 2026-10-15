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
| `examples/` | Runnable reference configurations: `minimal`, `full-stack`, `postgres-only`, `kafka-consumer`, `dragonfly-cache`. |
| `test/` | Shared test fixtures (currently the Kyverno guardrail fixtures under `test/kyverno/`). |
| `flux/` | Self-referential Flux GitOps bootstrap that syncs this repo into a cluster — see [flux/README.md](flux/README.md). |
| `hack/` | Repo automation scripts: `check-version-bump.sh` (PR version gate) and `lint-app.sh` (resolve the app chart against the local library). |
| `.github/workflows/` | CI/CD workflows (see [CI](#ci--cd)). |

## The charts

*   **[ksvc library chart](charts/library/ksvc/README.md)** — Knative Services,
    CloudNativePG, Kafka sources + DLQ, DragonflyDB, Flagger canaries, Ceph RGW
    object buckets, Kyverno admission policies. Its README is generated from
    `values.yaml` by [helm-docs](https://github.com/norwoodj/helm-docs) (`make docs`).
*   **ksvc-app application chart** (`charts/app/ksvc/`) — wraps `ksvc` so that
    consumers can `helm install` a normal chart. Pins a `ksvc` version via an
    `oci://ghcr.io/enchantednatures/charts` dependency.

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
    **`<chart>-v<version>`** (for example `ksvc-v0.7.1`) also triggers a release.
3.  **Dependent bump** — when a **library** chart is released, the
    `update-dependents` job opens a PR that bumps the library dependency (and the
    dependent app chart's patch version) and refreshes its `Chart.lock`.

Consumers reference a published chart by OCI repository and version:

```yaml
dependencies:
  - name: ksvc
    version: 0.7.1
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
make test                 # helm-unittest (145+ tests)
make docs                 # regenerate charts/library/ksvc/README.md (helm-docs, docker)
make update-locks         # refresh committed Chart.lock files
make template EXAMPLE=minimal

make create-kind-cluster  # Kind cluster + all CRDs
make install-local EXAMPLE=minimal
make install-flux-sync    # apply the flux/ GitOps bootstrap
```

## CI / CD

*   **Lint and Test** (`.github/workflows/lint-test.yaml`) — `make lint`,
    `make test`, JSON-schema validation of example values, template rendering,
    kubeconform validation, Kyverno policy tests, the PR chart-version gate, and
    a **docs check** that runs `make docs` and fails if the generated README is
    out of sync with `values.yaml`.
*   **Integration Test** (`.github/workflows/integration-test.yaml`) — nightly
    and PR Kind-cluster dry-runs for every example, plus a Kyverno guardrails
    end-to-end test.
*   **Release** (`.github/workflows/release.yaml`) — the OCI release pipeline
    described above.

## License

See the [LICENSE](LICENSE) file for the license governing this repository.
