#!/usr/bin/env bash
#
# lint-app.sh — resolve the app chart's ksvc dependency against the local
# library chart, run the caller-supplied command(s), then restore the chart
# metadata exactly as it was.
#
# charts/app/ksvc declares its `ksvc` dependency against the published OCI
# repository. To lint/render/test the app chart against the in-repo library, the
# dependency's repository is rewritten to a relative file:// path and its
# version is rewritten to the local library version (the published pin lags
# until the release workflow bumps the app chart), `helm dependency update` is
# run, and the supplied helm command(s) are executed.
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

# Resolve against the library chart in this worktree, not the published pin.
library_version="$(grep '^version:' charts/library/ksvc/Chart.yaml | head -1 | awk '{print $2}')"
if [ -z "$library_version" ]; then
  echo "lint-app.sh: could not read version from charts/library/ksvc/Chart.yaml" >&2
  exit 1
fi

sed -i 's|repository: oci://ghcr.io/enchantednatures/charts|repository: "file://../../library/ksvc"|' "$chart_yaml"

# The app chart's dependency version pins the last published library release.
# Rewrite only the version line inside the `- name: ksvc` dependency block so
# helm dependency update can resolve the local file:// chart; the chart's own
# top-level version line is left untouched.
sed -i "/^[[:space:]]*- name: ksvc$/,/^[[:space:]]*version:/ s|^\([[:space:]]*\)version:.*|\1version: ${library_version}|" "$chart_yaml"

helm dependency update "$chart_dir"

if [ "$#" -gt 0 ]; then
  "$@"
fi
