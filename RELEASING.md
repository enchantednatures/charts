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

## Local release checks

The release logic is covered without registry or OIDC access:

```bash
hack/release/test-release-gate.sh
hack/release/test-reconcile-release.sh
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
