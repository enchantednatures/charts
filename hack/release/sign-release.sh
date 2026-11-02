#!/usr/bin/env bash
#
# sign-release.sh — sign, attest, and attach an SBOM to a published chart.
#
# Runs after reconcile-release.sh has published the OCI artifact. The .tgz is
# pulled back from OCI so the SBOM describes exactly what consumers install.
# The artifact is signed with cosign keyless/OIDC, an SPDX JSON SBOM is attached
# to the OCI digest and uploaded to the GitHub Release, and an SLSA v1
# provenance attestation binds the OCI digest to the source repository, release
# commit, workflow, and chart version.
#
# Usage:
#   GITHUB_REPOSITORY=owner/repo hack/release/sign-release.sh \
#     --chart ksvc --version 1.0.0 --path charts/library/ksvc \
#     --tag ksvc-v1.0.0 --commit <sha> [--workdir <dir>]
#
# Any signing, SBOM, attestation, or upload failure exits non-zero.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
chart=""
version=""
chart_path=""
tag=""
commit=""
workdir="${RUNNER_TEMP:-/tmp}/release-supply-chain"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart) chart="${2:?--chart requires a value}"; shift 2 ;;
    --version) version="${2:?--version requires a value}"; shift 2 ;;
    --path) chart_path="${2:?--path requires a value}"; shift 2 ;;
    --tag) tag="${2:?--tag requires a value}"; shift 2 ;;
    --commit) commit="${2:?--commit requires a value}"; shift 2 ;;
    --workdir) workdir="${2:?--workdir requires a value}"; shift 2 ;;
    -h|--help)
      sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "sign-release.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for value in chart version chart_path tag commit; do
  if [ -z "${!value}" ]; then
    echo "::error::sign-release.sh: --${value//_/-} is required" >&2
    exit 2
  fi
done

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "::error::GITHUB_REPOSITORY is required to build the provenance predicate" >&2
  exit 2
fi

for tool in cosign syft helm gh jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "::error::sign-release.sh requires '$tool' on PATH" >&2
    exit 1
  fi
done

cd "$repo_root"

chart_yaml="$chart_path/Chart.yaml"
if [ ! -f "$chart_yaml" ]; then
  echo "::error::Chart metadata not found: $chart_yaml" >&2
  exit 1
fi

actual_version="$(grep '^version:' "$chart_yaml" | head -1 | awk '{print $2}')"
if [ "$actual_version" != "$version" ]; then
  echo "::error::$chart_yaml version is '$actual_version' but signing expects '$version'" >&2
  exit 1
fi

expected_tag="${chart}-v${version}"
if [ "$tag" != "$expected_tag" ]; then
  echo "::error::Release tag '$tag' does not match chart '$chart' version '$version' (expected '$expected_tag')" >&2
  exit 1
fi

if ! commit="$(git rev-parse --verify "${commit}^{commit}" 2>/dev/null)"; then
  echo "::error::Release commit '$commit' does not exist in this checkout" >&2
  exit 1
fi

registry="${REGISTRY:-ghcr.io}"
repository_owner="${GITHUB_REPOSITORY%%/*}"
chart_repository="${registry}/${repository_owner}/charts/${chart}"
oci_repository="oci://${registry}/${repository_owner}/charts"
image_ref="${chart_repository}:${version}"

if ! signature_ref="$(cosign triangulate "$image_ref" 2>/dev/null)"; then
  echo "::error::Could not resolve the OCI digest for $image_ref. Is the artifact published?" >&2
  exit 1
fi

digest=""
if [[ "$signature_ref" =~ :sha256-([0-9a-f]{64})\.sig$ ]]; then
  digest="${BASH_REMATCH[1]}"
fi
if [ -z "$digest" ]; then
  echo "::error::Could not derive a sha256 digest from cosign triangulate output: $signature_ref" >&2
  exit 1
fi
image_digest_ref="${chart_repository}@sha256:${digest}"

mkdir -p "$workdir"
pull_dir="$workdir/published"
rm -rf "$pull_dir"
mkdir -p "$pull_dir"
helm pull "${oci_repository}/${chart}" --version "$version" --destination "$pull_dir" >/dev/null

asset="$pull_dir/${chart}-${version}.tgz"
if [ ! -f "$asset" ]; then
  echo "::error::helm pull did not produce the expected asset: $asset" >&2
  exit 1
fi

sbom="$workdir/${chart}-${version}.spdx.json"
syft "$asset" -o "spdx-json=${sbom}" >/dev/null
if ! jq -e 'has("spdxVersion") and (.packages | length > 0)' "$sbom" >/dev/null; then
  echo "::error::Syft did not produce a usable SPDX JSON SBOM at $sbom" >&2
  exit 1
fi

workflow_ref="${GITHUB_WORKFLOW_REF:-${GITHUB_WORKFLOW:-unknown-workflow}}"
server_url="${GITHUB_SERVER_URL:-https://github.com}"
run_id="${GITHUB_RUN_ID:-unknown-run}"
source_ref="${GITHUB_REF:-unknown-ref}"

predicate="$workdir/${chart}-${version}.provenance.json"
jq -n \
  --arg server "$server_url" \
  --arg repo "$GITHUB_REPOSITORY" \
  --arg commit "$commit" \
  --arg source_ref "$source_ref" \
  --arg workflow "$workflow_ref" \
  --arg run_id "$run_id" \
  --arg chart "$chart" \
  --arg version "$version" \
  --arg path "$chart_path" \
  --arg oci "$image_ref" \
  --arg digest "$digest" \
  '{
    buildDefinition: {
      buildType: "https://slsa.dev/provenance/v1",
      externalParameters: {
        source: {
          repository: ($server + "/" + $repo),
          commit: $commit,
          ref: $source_ref
        },
        chart: {
          name: $chart,
          version: $version,
          path: $path
        },
        artifact: {
          reference: $oci,
          digest: {sha256: $digest}
        },
        workflow: {
          ref: $workflow,
          runId: $run_id
        }
      },
      resolvedDependencies: [
        {
          uri: ("git+" + $server + "/" + $repo + "@" + $commit),
          digest: {gitCommit: $commit}
        }
      ]
    },
    runDetails: {
      builder: {
        id: ($server + "/" + $workflow)
      },
      metadata: {
        invocationId: ($server + "/" + $repo + "/actions/runs/" + $run_id)
      }
    }
  }' > "$predicate"

if ! jq -e '.buildDefinition.externalParameters.artifact.digest.sha256 == $digest' \
  --arg digest "$digest" "$predicate" >/dev/null; then
  echo "::error::Generated provenance predicate does not bind the OCI digest" >&2
  exit 1
fi

echo "Signing $image_ref (digest sha256:${digest})"
cosign sign --yes "$image_ref"

echo "Attaching SPDX SBOM to $image_digest_ref"
cosign attach sbom --sbom "$sbom" --type spdxjson "$image_digest_ref"

echo "Attesting SLSA provenance to $image_digest_ref"
cosign attest --yes --predicate "$predicate" --type slsaprovenance1 "$image_digest_ref"

echo "Uploading SBOM and provenance to GitHub Release $tag"
gh release upload "$tag" "$sbom" "$predicate" \
  --repo "$GITHUB_REPOSITORY" \
  --clobber

echo "Signed and attested $chart v$version:"
echo "  OCI:        $image_ref"
echo "  Digest:     sha256:$digest"
echo "  SBOM:       $sbom"
echo "  Provenance: $predicate"
