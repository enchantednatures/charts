# ksvc-app

`ksvc-app` is a thin application chart that wraps the
[`ksvc` library chart](../../library/ksvc/README.md). Install it when you want
a normal `helm install`/`helm upgrade` workflow instead of copying the library
templates into your own chart.

The wrapper renders one or more Knative Services plus the optional supporting
resources the library already provides: CloudNativePG PostgreSQL, Kafka event
sources, DragonflyDB caches, object buckets, Knative eventing, and Flagger
canaries.

## Quick start

Install the published chart into a dedicated namespace, setting at least one
service image:

```bash
helm install my-svc oci://ghcr.io/enchantednatures/charts/ksvc-app \
  --version 1.0.0 \
  --namespace my-services \
  --create-namespace \
  --set services.api.image.repository=ghcr.io/my-org/my-app \
  --set services.api.image.tag=v1.0.0
```

The chart pins its `ksvc` library dependency to `1.0.0` in `Chart.yaml` (and
the digest in `Chart.lock`). The wrapper version and the dependency pin are
independent: the wrapper follows its own release line, while the dependency
advances when a new library release is adopted.

All values are provided at the chart root, exactly as they are for a chart that
embeds the library directly:

```bash
helm upgrade --install my-svc oci://ghcr.io/enchantednatures/charts/ksvc-app \
  --version 1.0.0 \
  --namespace my-services \
  --set services.api.image.repository=ghcr.io/my-org/my-app \
  --set services.api.image.tag=v1.1.0 \
  --set postgres.enabled=true \
  --set dragonfly.enabled=true
```

Do not nest the values under `ksvc:`. The dependency is a library chart, not a
subchart that owns a values namespace.

## Why `helm show values` is empty

The wrapper exists only to package and version the library. Its own
`values.yaml` contains comments but no defaults, so:

```bash
helm show values charts/app/ksvc
```

prints only that comment block, and the OCI equivalent is likewise empty. This
is intentional, not a broken chart.

Defaults come from the library's loader. `charts/app/ksvc/templates/common.yaml`
calls `ksvc.loader.generate`, which applies the library's own defaults through
`ksvc.loader.applyDefaults` before rendering anything. Read the
[library values reference](../../library/ksvc/README.md) for the complete set of
keys, defaults, and rendered resources.

## Validation

`ksvc-app` deliberately ships no `values.schema.json`. Copying the library
schema into the wrapper would duplicate it and drift. Validate values through
the following layers instead:

- **`helm lint`** checks chart metadata, the dependency, and that the templates
  render. It does not validate consumer values against the library's
  `values.schema.json`; Helm does not apply a library chart's schema to values
  passed through a consumer chart.
- **`helm template`** renders the full manifest set, which is the same output
  `helm install` sends to the cluster.
- **Render-time validators** in the library
  (`templates/lib/_validators.tpl`) enforce required fields, cross-references
  between services and event sources, scaling bounds, and certificate
  configuration. These run during every render and fail the install with an
  explanatory message.

The library README's schema note describes the same limitation from the library
side. Rely on the render-time validators for values that must be rejected.

## Testing the wrapper locally

The committed dependency points at the published OCI repository, so the app
chart is normally tested against the published library. To test it against the
library source in this repository, use the wrapper script:

```bash
hack/lint-app.sh helm lint charts/app/ksvc
hack/lint-app.sh helm template test-app charts/app/ksvc \
  --namespace test-ns \
  --set services.api.image.repository=ghcr.io/test/app \
  --set services.api.image.tag=v1.0.0
make test-app
```

`hack/lint-app.sh` first verifies that the committed `Chart.lock` matches
`Chart.yaml`, then rewrites the dependency to the local library, runs the
command, and restores the original files on exit. `make test-app` runs the
helm-unittest render suite in [`tests/app_test.yaml`](tests/app_test.yaml)
through that script. CI runs the same suite for both the Helm 3.17 and Helm 4.3
lanes, and the release workflow runs it against the pinned dependency after
building it.

## Further reading

- [Library values reference and rendered resources](../../library/ksvc/README.md)
- [Migration guide from 0.5.0 to 1.0.0](../../../MIGRATION.md)
- [Versioning and deprecation policy](../../../CONTRIBUTING.md#versioning-and-deprecation)
