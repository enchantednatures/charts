#!/usr/bin/env bash
#
# check-kube-version.sh — verify every consumable chart enforces the documented
# Kubernetes floor.
#
# Helm evaluates `kubeVersion` on the root chart only. The library chart's
# constraint therefore does not protect consumers who install an example or the
# app wrapper; each root chart must declare it. This script renders every
# example and the app chart at 1.27.0 (must fail) and 1.28.0 (must succeed).
#
# Usage:
#   hack/check-kube-version.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

constraint="$(sed -n 's/^kubeVersion:[[:space:]]*">=\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' charts/library/ksvc/Chart.yaml | head -1)"
if [ -z "$constraint" ]; then
  echo "FAIL: cannot read kubeVersion from charts/library/ksvc/Chart.yaml" >&2
  exit 1
fi

min_version="${constraint}.0"
too_old="$(awk -F. '{printf "%s.%d.0", $1, $2 - 1}' <<< "$constraint")"
failures=0

for chart in examples/*/Chart.yaml charts/app/ksvc/Chart.yaml; do
  if ! grep -q '^kubeVersion:' "$chart"; then
    echo "FAIL: $chart does not declare kubeVersion" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "check-kube-version: missing kubeVersion constraint(s)" >&2
  exit 1
fi

check() {
  local name="$1"
  shift
  local -a cmd=("$@")

  if "${cmd[@]}" --kube-version "$too_old" >/dev/null 2>&1; then
    echo "FAIL: $name renders with Kubernetes $too_old (expected rejection)"
    failures=$((failures + 1))
  else
    echo "OK: $name rejects Kubernetes $too_old"
  fi

  if ! "${cmd[@]}" --kube-version "$min_version" >/dev/null 2>&1; then
    echo "FAIL: $name does not render with Kubernetes $min_version"
    failures=$((failures + 1))
  else
    echo "OK: $name renders with Kubernetes $min_version"
  fi
}

for example in examples/*/; do
  [ -f "$example/Chart.yaml" ] || continue
  helm dependency build "$example" >/dev/null
  name="$(basename "$example")"
  check "example $name" helm template kube-version-check "$example" --namespace test-ns
done

# The app chart resolves its dependency against the local library via
# hack/lint-app.sh (the committed OCI pin can lag until the release bot bumps
# it). Run both renders through one invocation so the dependency is resolved
# only once.
if ! hack/lint-app.sh bash -c '
  set -euo pipefail
  common=(helm template kube-version-check charts/app/ksvc --namespace test-ns
          --set services.api.image.repository=example/app)
  if "${common[@]}" --kube-version 1.27.0 >/dev/null 2>&1; then
    echo "FAIL: app chart renders with Kubernetes 1.27.0 (expected rejection)" >&2
    exit 1
  fi
  echo "OK: app chart rejects Kubernetes 1.27.0"
  "${common[@]}" --kube-version 1.28.0 >/dev/null
  echo "OK: app chart renders with Kubernetes 1.28.0"
'; then
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "check-kube-version: $failures check(s) failed" >&2
  exit 1
fi

echo "check-kube-version: OK"
