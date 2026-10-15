#!/usr/bin/env bash
#
# lint-app.sh — resolve the app chart's ksvc dependency against the local
# library chart, run the caller-supplied command(s), then restore the chart
# metadata exactly as it was.
#
# charts/app/ksvc declares its `ksvc` dependency against the published OCI
# repository. To lint/render/test the app chart against the in-repo library, the
# repository is rewritten to a relative file:// path, `helm dependency update`
# is run, and the supplied helm command(s) are executed.
#
# The original Chart.yaml (and Chart.lock, if present) is always restored, from
# a snapshot taken before any mutation, via a trap on EXIT — including when a
# command fails or the script is interrupted. This keeps the working tree
# unchanged and, unlike the `git checkout` this replaces, never destroys a
# developer's uncommitted edits.
#
# Usage:
#   hack/lint-app.sh <command...>
#
# Examples:
#   hack/lint-app.sh helm lint charts/app/ksvc
#   hack/lint-app.sh helm unittest charts/app/ksvc
#
# With no command it only resolves the dependency (e.g. to populate
# charts/app/ksvc/charts/ for a later step) and then restores.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

chart_dir="charts/app/ksvc"
chart_yaml="$chart_dir/Chart.yaml"
chart_lock="$chart_dir/Chart.lock"

# Snapshot the chart metadata before mutating anything so the restore is exact.
snapshot="$(mktemp -d)"
snapshot_yaml="$snapshot/Chart.yaml"
snapshot_lock="$snapshot/Chart.lock"

had_lock=0
cp "$chart_yaml" "$snapshot_yaml"
if [ -f "$chart_lock" ]; then
  cp "$chart_lock" "$snapshot_lock"
  had_lock=1
fi

restore() {
  cp "$snapshot_yaml" "$chart_yaml"
  if [ "$had_lock" -eq 1 ]; then
    cp "$snapshot_lock" "$chart_lock"
  else
    rm -f "$chart_lock"
  fi
  rm -rf "$snapshot"
}
trap restore EXIT

sed -i 's|repository: oci://ghcr.io/enchantednatures/charts|repository: "file://../../library/ksvc"|' "$chart_yaml"

helm dependency update "$chart_dir"

if [ "$#" -gt 0 ]; then
  "$@"
fi
