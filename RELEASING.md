# Releasing and verifying charts

`release.yaml` publishes each chart to GHCR as an OCI artifact and then attaches
supply-chain metadata to the exact published artifact:

| Artifact | How it is produced | Where to find it |
|----------|--------------------|------------------|
| OCI chart | `helm package` + `helm push` in `hack/release/reconcile-release.sh` | `oci://ghcr.io/enchantednatures/charts/<chart>:<version>` |
| Signature | `cosign sign --yes <registry>/<owner>/charts/<chart>:<version>` (keyless/OIDC) | OCI signature tag `sha256-<digest>.sig` |
| SBOM | Syft SPDX JSON scan of the published `.tgz` | `cosign attach sbom` on the OCI digest and a GitHub Release asset |
| Provenance | `cosign attest --type slsaprovenance1` with a predicate binding the OCI digest, source repository, release commit, workflow, and chart version | OCI attestation and a GitHub Release asset |

The sign/attest step runs after reconciliation on every release, including
`workflow_dispatch` repair runs, so a repaired release gets the same metadata as
a fresh publish. Any signing, SBOM, attestation, or upload failure fails the
release job.

## Verifying a release

Set the chart and version, then run the commands below. The identity regexp
covers both `main` pushes and `<chart>-v<version>` tag pushes.

```bash
CHART=ksvc
VERSION=1.0.0
REF="ghcr.io/enchantednatures/charts/${CHART}:${VERSION}"
IDENTITY='^https://github\.com/enchantednatures/charts/\.github/workflows/release\.yaml@refs/(heads/main|tags/.+)$'
ISSUER='https://token.actions.githubusercontent.com'
```

### Signature

```bash
cosign verify "$REF" \
  --certificate-identity-regexp "$IDENTITY" \
  --certificate-oidc-issuer "$ISSUER"
```

### Attestation and provenance

```bash
cosign verify-attestation --type slsaprovenance1 "$REF" \
  --certificate-identity-regexp "$IDENTITY" \
  --certificate-oidc-issuer "$ISSUER"
```

Inspect the predicate to check the bound digest, repository, commit, workflow,
and chart version:

```bash
cosign verify-attestation --type slsaprovenance1 "$REF" \
  --certificate-identity-regexp "$IDENTITY" \
  --certificate-oidc-issuer "$ISSUER" \
  | jq -r '.payload | @base64d | fromjson | .predicate
      | .buildDefinition.externalParameters
      | {artifact, source, chart, workflow}'
```

### SBOM

Download the attached SBOM and compare it with the GitHub Release asset:

```bash
cosign download sbom "$REF" > /tmp/ksvc.spdx.json
gh release download "${CHART}-v${VERSION}" --pattern '*.spdx.json' --dir /tmp
diff -u <(jq -S . /tmp/ksvc.spdx.json) \
        <(jq -S . "/tmp/${CHART}-${VERSION}.spdx.json")
```

`cosign tree "$REF"` lists the signature, SBOM, and attestation attached to the
image.

## Post-publish OCI end-to-end

`release.yaml` runs an `e2e` job for every chart in the release matrix after the
reconcile/sign job succeeds. The job always pulls the **published** artifact
from GHCR by version; it never substitutes a local render:

| Released chart type | What the job installs |
|---------------------|-----------------------|
| library (`ksvc`) | A temporary consumer chart whose `Chart.yaml` declares an OCI dependency on the released `ksvc` version and whose `templates/common.yaml` calls the loader template. |
| application (`ksvc-app`) | The published `ksvc-app` chart directly from GHCR at the released version. |

The flow is:

1. Create a Kind cluster pinned to `kindest/node:v1.32.0`.
2. Install the Knative Serving CRDs with `make install-knative`.
3. Discover the previous published version of the same chart from the registry
   (`hack/release/find-previous-version.sh`, SemVer ordering).
4. If a previous version exists, install it, upgrade to the released version,
   assert the rendered Knative Service image and Helm revision changed, then
   `helm rollback` and assert the image reverted.
5. If no previous version exists, emit a workflow annotation and run the
   install/uninstall smoke test only. Discovery is still attempted; a registry
   error fails the job instead of being treated as a first-ever release.
6. Uninstall and assert both the Helm release and the Knative Services labelled
   for that release are gone.

Only the Serving CRDs are required for this path: no Postgres, Kafka, Dragonfly,
or Flagger operators are installed, and no external images are pulled by the
Knative Service. Without the Serving controller the Knative Service does not
become `Ready`, so rollout is verified structurally through the Helm revision
and the Knative Service `spec.template.spec.containers[0].image` value.

To run the same check locally against an already-published version:

```bash
kind create cluster --name release-e2e --image kindest/node:v1.32.0
make install-knative
helm registry login ghcr.io --username "$GITHUB_ACTOR" --password-stdin <<<"$GITHUB_TOKEN"

hack/release/e2e-oci-install.sh \
  --chart ksvc --version 1.0.0 --chart-type library \
  --oci-repository oci://ghcr.io/enchantednatures/charts \
  --release-name release-e2e --namespace release-e2e
```

Use `--chart ksvc-app --chart-type application` to exercise the published app
chart. Add `--previous-version <version>` to pin N-1 instead of discovering it
from the registry. Supplying an empty value (`--previous-version ""`) exercises
the first-release path. `REGISTRY_TOKEN`/`REGISTRY_USERNAME` are honoured for
private registries.

The local test suite validates the control flow, version discovery, and cleanup
assertions with fake executables; a real OCI e2e requires a published artifact
and a Kind cluster, so it is only run by CI.

## Dependent bump PR

When a library chart is released from a push to `main` or from a
`<chart>-v<version>` tag, `update-dependents` checks out the **release commit**,
bumps each dependent app chart (dependency pin and patch version), runs
`make update-locks`, and opens one PR. The PR refreshes:

* `charts/app/*/Chart.lock`
* `charts/library/*/test-chart/Chart.lock`
* `examples/*/Chart.lock`

The job verifies every refreshed lock with `helm dependency build` before
committing and fails if a build rewrites a lock or if the PR cannot be opened.

**Required secret:** configure `RELEASE_BOT_TOKEN` as a GitHub App token or a
PAT with `contents: write` and `pull-requests: write`. The token is used for the
branch push and PR creation, which is what makes the resulting PR trigger
`pull_request` CI. If the secret is absent the job falls back to `GITHUB_TOKEN`
and logs a notice: the PR is still created, but GitHub may suppress the CI runs
for a `GITHUB_TOKEN`-authored PR. No token is hardcoded in the workflow.

## Local release checks

The release logic is covered without registry or OIDC access:

```bash
hack/release/test-release-gate.sh
hack/release/test-reconcile-release.sh
hack/release/test-find-previous-version.sh
hack/release/test-update-dependents.sh
hack/release/test-e2e-oci-install.sh
```

`hack/release/test-reconcile-release.sh` also asserts that semver prerelease
versions (for example `1.0.0-rc.1`) create GitHub Releases with
`--prerelease --latest=false`, while stable versions are never marked
prerelease.

Cosign, Syft, and GitHub OIDC signing cannot be exercised locally without a
published artifact and a workflow identity token; CI validates the pinned
installers, the workflow wiring, and the fail-closed script.

## Pinned supply-chain tooling

| Tool | Pin |
|------|-----|
| cosign | `sigstore/cosign-installer` pinned by commit SHA, cosign `v3.1.4` |
| Syft | `anchore/sbom-action/download-syft` pinned by commit SHA, Syft `v1.55.0` |
| Python CI deps | [`requirements-ci.txt`](requirements-ci.txt) (`==` pins) |
| kubeconform | `v0.8.0` plus SHA-256 verification in `lint-test.yaml` |
| helm-docs | image digest pinned in the `Makefile` |

All GitHub Actions used by the workflows are pinned to full 40-character commit
SHAs; `hack/check-action-pins.sh` fails CI if a floating tag is introduced.
