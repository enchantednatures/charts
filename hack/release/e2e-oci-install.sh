#!/usr/bin/env bash
#
# e2e-oci-install.sh — install/upgrade/rollback/uninstall a chart pulled from
# the published OCI registry.
#
# The workflow creates a Kind cluster and installs the Knative Serving CRDs
# before this script runs; the script itself only uses helm and kubectl. It
# never renders a local chart for the released artifact:
#
#   library charts      a temporary consumer chart declares an OCI dependency on
#                       the released library version and renders the loader
#                       template (the same contract a consumer uses).
#   application charts  the published application chart is installed directly
#                       from the OCI repository at the released version.
#
# The previous published version is discovered from the registry unless it is
# supplied with --previous-version. When no lower version exists, the script
# logs an annotation and runs install/uninstall only; discovery failures still
# fail the run.
#
# Knative Serving CRDs are enough for this minimal path. Without the Serving
# controller the Knative Service does not become Ready, so "rollout" is verified
# structurally: Helm's revision plus the rendered Knative Service image changes
# on upgrade and reverts on rollback.
#
# Usage:
#   hack/release/e2e-oci-install.sh \
#     --chart ksvc --version 1.0.0 --chart-type library \
#     --oci-repository oci://ghcr.io/enchantednatures/charts \
#     --release-name release-e2e --namespace release-e2e
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chart=""
version=""
chart_type=""
oci_repository=""
release_name="release-e2e"
namespace="release-e2e"
image_repository="ghcr.io/example-org/release-e2e"
previous_version=""
previous_version_supplied=false
workdir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --chart) chart="${2:?--chart requires a value}"; shift 2 ;;
    --version) version="${2:?--version requires a value}"; shift 2 ;;
    --chart-type) chart_type="${2:?--chart-type requires a value}"; shift 2 ;;
    --oci-repository) oci_repository="${2:?--oci-repository requires a value}"; shift 2 ;;
    --release-name) release_name="${2:?--release-name requires a value}"; shift 2 ;;
    --namespace) namespace="${2:?--namespace requires a value}"; shift 2 ;;
    --image-repository) image_repository="${2:?--image-repository requires a value}"; shift 2 ;;
    --previous-version) previous_version="${2:-}"; previous_version_supplied=true; shift 2 ;;
    --workdir) workdir="${2:?--workdir requires a value}"; shift 2 ;;
    -h|--help)
      sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "e2e-oci-install.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for value in chart version chart_type oci_repository; do
  if [ -z "${!value}" ]; then
    echo "::error::e2e-oci-install.sh: --${value//_/-} is required" >&2
    exit 2
  fi
done

case "$chart_type" in
  library|application) ;;
  *)
    echo "::error::e2e-oci-install.sh: --chart-type must be 'library' or 'application' (got '$chart_type')" >&2
    exit 2
    ;;
esac

if [ "$chart_type" = "library" ] && [ "$chart" != "ksvc" ]; then
  echo "::error::e2e-oci-install.sh: consumer mode renders the ksvc loader template, so it currently supports only the 'ksvc' library chart (got '$chart')" >&2
  exit 2
fi

for tool in helm kubectl python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "::error::e2e-oci-install.sh requires '$tool' on PATH" >&2
    exit 1
  fi
done

workdir="${workdir:-${RUNNER_TEMP:-/tmp}/release-e2e-${chart}}"
if [ -z "$workdir" ] || [ "$workdir" = "/" ]; then
  echo "::error::e2e-oci-install.sh: refusing unsafe --workdir '$workdir'" >&2
  exit 2
fi
mkdir -p "$workdir"
rm -rf "$workdir/consumer-previous" "$workdir/consumer-current"
mkdir -p "$workdir/consumer-previous/templates" "$workdir/consumer-current/templates"

oci_base="${oci_repository%/}"
released_ref="${oci_base}/${chart}"
service_name="${release_name}-api"
image_ref="${image_repository}:"

log() {
  echo "e2e-oci-install: $*"
}

fail() {
  echo "::error::e2e-oci-install: $*" >&2
  exit 1
}

release_revision() {
  helm status "$release_name" --namespace "$namespace" --output json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])'
}

release_chart_version() {
  helm get metadata "$release_name" --namespace "$namespace" --output json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])'
}

kservice_image() {
  kubectl get kservice "$service_name" --namespace "$namespace" \
    --output jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true
}

assert_revision() {
  local expected="$1" actual
  actual="$(release_revision)"
  [ "$actual" = "$expected" ] \
    || fail "Helm release $release_name is at revision $actual, expected $expected"
  log "Helm revision is $expected"
}

assert_image() {
  local expected="$1" actual
  actual="$(kservice_image)"
  [ "$actual" = "$expected" ] \
    || fail "Knative Service $service_name runs image '$actual', expected '$expected'"
  log "Knative Service $service_name runs $expected"
}

assert_chart_version() {
  local expected="$1" actual
  actual="$(release_chart_version)"
  [ "$actual" = "$expected" ] \
    || fail "Helm release $release_name installed chart version $actual, expected $expected"
  log "Installed chart version is $expected"
}

make_consumer_chart() {
  local target="$1" dependency_version="$2"
  cat > "$target/Chart.yaml" <<EOF
apiVersion: v2
name: ksvc-release-e2e-consumer
description: Temporary consumer chart used by the post-publish release e2e
type: application
version: 0.0.0
dependencies:
  - name: ksvc
    version: ${dependency_version}
    repository: ${oci_base}
EOF
  cat > "$target/templates/common.yaml" <<'EOF'
{{- include "ksvc.loader.generate" . }}
EOF
  helm dependency build "$target" >/dev/null
  grep -q "version: ${dependency_version}" "$target/Chart.lock" \
    || fail "consumer Chart.lock does not pin ksvc ${dependency_version}"
  log "Built temporary consumer chart pinned to ksvc ${dependency_version}"
}

prepare_source() {
  local target_version="$1" suffix="$2"
  if [ "$chart_type" = "application" ]; then
    SOURCE="$released_ref"
    SOURCE_VERSION="$target_version"
    return 0
  fi

  local target="$workdir/consumer-${suffix}"
  make_consumer_chart "$target" "$target_version"
  SOURCE="$target"
  SOURCE_VERSION=""
}

helm_install() {
  local tag="$1"
  local args=(
    install "$release_name" "$SOURCE"
    --namespace "$namespace"
    --create-namespace
    --set-string "services.api.image.repository=${image_repository}"
    --set-string "services.api.image.tag=${tag}"
  )
  if [ -n "$SOURCE_VERSION" ]; then
    args+=(--version "$SOURCE_VERSION")
  fi
  helm "${args[@]}"
}

helm_upgrade() {
  local tag="$1"
  local args=(
    upgrade "$release_name" "$SOURCE"
    --namespace "$namespace"
    --set-string "services.api.image.repository=${image_repository}"
    --set-string "services.api.image.tag=${tag}"
  )
  if [ -n "$SOURCE_VERSION" ]; then
    args+=(--version "$SOURCE_VERSION")
  fi
  helm "${args[@]}"
}

# Ensure a stale local release cannot confuse the assertions if the job is
# re-run against a reused cluster.
helm uninstall "$release_name" --namespace "$namespace" >/dev/null 2>&1 || true
kubectl delete kservice "$service_name" --namespace "$namespace" --ignore-not-found >/dev/null 2>&1 || true

log "Pulling $chart v$version from $released_ref"
helm show chart "$released_ref" --version "$version" >/dev/null \
  || fail "published OCI artifact $released_ref:$version is not pullable"

if [ "$previous_version_supplied" = false ]; then
  log "Discovering the previous published version of $chart"
  previous_version="$("${script_dir}/find-previous-version.sh" \
    --repository "${released_ref#oci://}" \
    --current "$version")"
fi

if [ -n "$previous_version" ]; then
  log "Installing previous published version $previous_version"
  helm show chart "$released_ref" --version "$previous_version" >/dev/null \
    || fail "previous published OCI artifact $released_ref:$previous_version is not pullable"
  prepare_source "$previous_version" previous
  helm_install "previous"
  if [ "$chart_type" = "application" ]; then
    assert_chart_version "$previous_version"
  fi
  assert_image "${image_ref}previous"

  log "Upgrading to released version $version"
  prepare_source "$version" current
  helm_upgrade "current"
  if [ "$chart_type" = "application" ]; then
    assert_chart_version "$version"
  fi
  assert_revision "2"
  assert_image "${image_ref}current"

  log "Rolling back to revision 1"
  helm rollback "$release_name" 1 --namespace "$namespace" >/dev/null
  assert_revision "3"
  assert_image "${image_ref}previous"
else
  echo "::notice::No previous published version of ${chart} lower than ${version} was found; skipping the N-1 upgrade and rollback. Install/uninstall smoke test still runs."
  prepare_source "$version" current
  helm_install "current"
  if [ "$chart_type" = "application" ]; then
    assert_chart_version "$version"
  fi
  assert_revision "1"
  assert_image "${image_ref}current"
fi

log "Uninstalling $release_name"
helm uninstall "$release_name" --namespace "$namespace" >/dev/null
if helm status "$release_name" --namespace "$namespace" >/dev/null 2>&1; then
  fail "Helm release $release_name still exists after uninstall"
fi
if kubectl get kservice "$service_name" --namespace "$namespace" >/dev/null 2>&1; then
  fail "Knative Service $service_name still exists after uninstall"
fi
remaining="$(kubectl get kservice --namespace "$namespace" \
  --selector "app.kubernetes.io/instance=${release_name}" \
  --output name 2>/dev/null | wc -l | tr -d ' ' || true)"
[ "$remaining" = "0" ] \
  || fail "$remaining Knative Service(s) labelled for $release_name remain after uninstall"
log "Uninstall removed the Helm release and all Knative Services for $release_name"
log "Post-publish OCI e2e passed for $chart v$version"
