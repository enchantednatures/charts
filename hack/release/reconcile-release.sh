#!/usr/bin/env bash
#
# reconcile-release.sh — independently reconcile the three release artifacts:
# the OCI chart, the git tag, and the GitHub Release.
#
# Each artifact is checked independently. Existing artifacts are never
# overwritten; missing artifacts are created. An existing tag must point at the
# expected release commit (the commit that produced the chart version), not
# merely at whatever HEAD happens to be.
#
# Usage:
#   hack/release/reconcile-release.sh \
#     --chart ksvc --version 1.0.0 --path charts/library/ksvc \
#     --type library --tag ksvc-v1.0.0 --commit <sha> [--repair]
#
# --repair requires the OCI artifact to already exist and is intended for
# workflow_dispatch runs that only repair a missing tag or GitHub Release.
#
# Application charts wait for their ksvc dependency to exist in OCI before
# packaging, then assert the packaged chart pins that same version. Tune the
# wait with:
#   DEPENDENCY_WAIT_ATTEMPTS          (default 60)
#   DEPENDENCY_WAIT_INTERVAL_SECONDS  (default 10)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
chart=""
version=""
chart_path=""
chart_type=""
tag=""
commit=""
repair=false
workdir="${RUNNER_TEMP:-/tmp}/release-charts"
dep_wait_attempts="${DEPENDENCY_WAIT_ATTEMPTS:-60}"
dep_wait_interval="${DEPENDENCY_WAIT_INTERVAL_SECONDS:-10}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart) chart="${2:?--chart requires a value}"; shift 2 ;;
    --version) version="${2:?--version requires a value}"; shift 2 ;;
    --path) chart_path="${2:?--path requires a value}"; shift 2 ;;
    --type) chart_type="${2:?--type requires a value}"; shift 2 ;;
    --tag) tag="${2:?--tag requires a value}"; shift 2 ;;
    --commit) commit="${2:?--commit requires a value}"; shift 2 ;;
    --repo-root) repo_root="${2:?--repo-root requires a value}"; shift 2 ;;
    --workdir) workdir="${2:?--workdir requires a value}"; shift 2 ;;
    --repair) repair=true; shift ;;
    -h|--help)
      sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "reconcile-release.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for value in chart version chart_path chart_type tag commit; do
  if [ -z "${!value}" ]; then
    echo "::error::reconcile-release.sh: --${value//_/-} is required" >&2
    exit 2
  fi
done

case "$dep_wait_attempts" in
  ''|*[!0-9]*)
    echo "::error::DEPENDENCY_WAIT_ATTEMPTS must be a non-negative integer (got '$dep_wait_attempts')" >&2
    exit 2
    ;;
esac
case "$dep_wait_interval" in
  ''|*[!0-9]*)
    echo "::error::DEPENDENCY_WAIT_INTERVAL_SECONDS must be a non-negative integer (got '$dep_wait_interval')" >&2
    exit 2
    ;;
esac
if [ "$dep_wait_attempts" -lt 1 ]; then
  echo "::error::DEPENDENCY_WAIT_ATTEMPTS must be at least 1" >&2
  exit 2
fi

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "::error::GITHUB_REPOSITORY is required for GitHub Release reconciliation" >&2
  exit 2
fi

cd "$repo_root"

chart_yaml="$chart_path/Chart.yaml"
if [ ! -f "$chart_yaml" ]; then
  echo "::error::Chart metadata not found: $chart_yaml" >&2
  exit 1
fi

actual_version="$(grep '^version:' "$chart_yaml" | head -1 | awk '{print $2}')"
if [ "$actual_version" != "$version" ]; then
  echo "::error::$chart_yaml version is '$actual_version' but the release expects '$version'" >&2
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

if git remote get-url origin >/dev/null 2>&1; then
  git fetch --tags --force origin >/dev/null
fi

tag_exists=false
tag_commit=""
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  tag_exists=true
  tag_commit="$(git rev-parse "${tag}^{commit}")"
  if [ "$tag_commit" != "$commit" ]; then
    echo "::error::Tag $tag points at $tag_commit but the expected release commit is $commit. Refusing to move or reuse the tag; investigate the release history." >&2
    exit 1
  fi
fi

registry="${REGISTRY:-ghcr.io}"
repository_owner="${GITHUB_REPOSITORY%%/*}"
oci_repository="oci://${registry}/${repository_owner}/charts"
oci_ref="${oci_repository}/${chart}"

read_dependency_version() {
  local chart_file="$1"
  local dependency_name="$2"
  awk -v dependency="$dependency_name" '
    BEGIN { in_dependencies = 0; in_item = 0 }
    /^dependencies:[[:space:]]*$/ { in_dependencies = 1; in_item = 0; next }
    in_dependencies && /^[^[:space:]-]/ { in_dependencies = 0; in_item = 0 }
    in_dependencies && /^[[:space:]]+-[[:space:]]*name:[[:space:]]*/ {
      name = $0
      sub(/^[[:space:]]+-[[:space:]]*name:[[:space:]]*/, "", name)
      gsub(/["\047]/, "", name)
      in_item = (name == dependency)
      next
    }
    in_item && /^[[:space:]]+version:[[:space:]]*/ {
      version = $0
      sub(/^[[:space:]]+version:[[:space:]]*/, "", version)
      gsub(/["\047]/, "", version)
      sub(/[[:space:]]+#.*$/, "", version)
      print version
      exit
    }
  ' "$chart_file"
}

wait_for_oci_dependency() {
  local app_chart="$1"
  local dependency_name="$2"
  local dependency_version="$3"
  local dependency_ref="${oci_repository}/${dependency_name}"
  local attempt=1
  local max_seconds=$((dep_wait_attempts * dep_wait_interval))

  while [ "$attempt" -le "$dep_wait_attempts" ]; do
    if helm show chart "$dependency_ref" --version "$dependency_version" >/dev/null 2>&1; then
      echo "Dependency ${dependency_name} v${dependency_version} is available in OCI for ${app_chart}."
      return 0
    fi
    if [ "$attempt" -lt "$dep_wait_attempts" ]; then
      sleep "$dep_wait_interval"
    fi
    attempt=$((attempt + 1))
  done

  echo "::error::Application chart ${app_chart} requires ${dependency_name} v${dependency_version}, but it was not published at ${dependency_ref}:${dependency_version} after ${dep_wait_attempts} attempts (~${max_seconds}s). Ensure the ${dependency_name} release finishes before the application chart packages." >&2
  return 1
}

assert_packaged_dependency_version() {
  local asset="$1"
  local app_chart="$2"
  local dependency_name="$3"
  local expected_version="$4"
  local packaged_manifest packaged_version

  if ! packaged_manifest="$(tar -xOzf "$asset" "${app_chart}/Chart.yaml" 2>/dev/null)"; then
    echo "::error::Could not read ${app_chart}/Chart.yaml from packaged asset ${asset}" >&2
    return 1
  fi

  packaged_version="$(printf '%s\n' "$packaged_manifest" | read_dependency_version /dev/stdin "$dependency_name")"
  if [ -z "$packaged_version" ]; then
    echo "::error::Packaged ${app_chart} asset does not declare a ${dependency_name} dependency; expected v${expected_version}." >&2
    return 1
  fi

  if [ "$packaged_version" != "$expected_version" ]; then
    echo "::error::Packaged ${app_chart} asset pins ${dependency_name} v${packaged_version} but the release expects v${expected_version}. Refusing to publish a package built against the wrong dependency version." >&2
    return 1
  fi

  echo "Packaged ${app_chart} pins ${dependency_name} v${expected_version} as expected."
}

oci_exists=false
if helm show chart "$oci_ref" --version "$version" >/dev/null 2>&1; then
  oci_exists=true
fi

release_exists=false
if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  release_exists=true
fi

if [ "$repair" = true ] && [ "$oci_exists" = false ]; then
  echo "::error::Repair mode requires $oci_ref:$version to already exist; OCI artifact not found. Re-run without repair to publish it." >&2
  exit 1
fi

if [ "$oci_exists" = true ] && [ "$tag_exists" = true ] && [ "$release_exists" = true ]; then
  echo "Already reconciled: $chart v$version (OCI, tag $tag at $commit, GitHub Release) all exist."
  exit 0
fi

need_package=false
if [ "$oci_exists" = false ] || [ "$release_exists" = false ]; then
  need_package=true
fi

asset="$workdir/${chart}-${version}.tgz"
if [ "$need_package" = true ]; then
  mkdir -p "$workdir"
  rm -f "$asset"

  dependency_version=""
  if [ "$chart_type" = "application" ]; then
    dependency_version="$(read_dependency_version "$chart_yaml" ksvc)"
    if [ -z "$dependency_version" ]; then
      echo "::error::Application chart ${chart} does not declare a ksvc dependency in ${chart_yaml}" >&2
      exit 1
    fi

    wait_for_oci_dependency "$chart" ksvc "$dependency_version"
    helm dependency build "$chart_path"
  fi

  helm package "$chart_path" --destination "$workdir"

  if [ ! -f "$asset" ]; then
    echo "::error::helm package did not produce the expected asset: $asset" >&2
    exit 1
  fi

  if [ "$chart_type" = "application" ]; then
    assert_packaged_dependency_version "$asset" "$chart" ksvc "$dependency_version"
  fi
fi

if [ "$oci_exists" = false ]; then
  echo "OCI artifact missing; pushing $chart v$version"
  helm push "$asset" "$oci_repository"
fi

if [ "$tag_exists" = false ]; then
  echo "Tag missing; creating $tag at release commit $commit"
  git tag "$tag" "$commit"
  git push origin "refs/tags/${tag}"
fi

if [ "$release_exists" = false ]; then
  echo "GitHub Release missing; creating $tag"
  gh release create "$tag" "$asset" \
    --repo "$GITHUB_REPOSITORY" \
    --title "$chart v$version" \
    --generate-notes
fi

echo "Reconciled $chart v$version:"
echo "  OCI:             $oci_ref:$version (was $([ "$oci_exists" = true ] && echo present || echo created))"
echo "  Tag:             $tag -> $commit (was $([ "$tag_exists" = true ] && echo present || echo created))"
echo "  GitHub Release:  $tag (was $([ "$release_exists" = true ] && echo present || echo created))"
