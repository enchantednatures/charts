#!/usr/bin/env bash
#
# test-upgrade-dry-run.sh — exercise `helm upgrade --dry-run` with the chart's
# own defaults and with values from a generated managed-Kafka project.
#
# Helm does not apply a library chart's values.schema.json to values supplied
# through a consumer wrapper. To reproduce the consumer shape that failed in
# issue #149 (and to make Helm enforce the schema), this script builds a
# temporary application chart that vendors the library templates and copies the
# library schema to the chart root. It then runs the upgrade action against:
#
#   1. the library's values.yaml plus the minimum required image, and
#   2. examples/generated-managed-kafka/values.yaml.
#
# Finally it renders the ksvc-app wrapper through the local dependency, so the
# documented app-chart install/upgrade path is exercised too.
#
# Helm 3 contacts the API server for capability discovery even with
# --dry-run=client, so this test expects a reachable cluster (CI creates a Kind
# cluster; no CRDs are required because rendering stays local).
#
# Usage:
#   hack/test-upgrade-dry-run.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v helm >/dev/null 2>&1; then
  echo "test-upgrade-dry-run: helm is required on PATH" >&2
  exit 1
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/ksvc-upgrade-dry-run.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

consumer="$workdir/consumer"
mkdir -p "$consumer/templates"

# Vendor the library templates instead of using a chart dependency: a library
# dependency's values appear under the dependency key and are not validated by
# the parent schema, while a copied-library consumer validates the release
# values at the chart root.
cp -R charts/library/ksvc/templates/. "$consumer/templates/"
printf '{{- include "ksvc.loader.generate" . }}\n' \
  > "$consumer/templates/common.yaml"
cp charts/library/ksvc/values.schema.json "$consumer/values.schema.json"

cat > "$consumer/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc-schema-consumer
description: Temporary chart used by hack/test-upgrade-dry-run.sh
type: application
version: 0.0.0
kubeVersion: ">=1.28.0"
EOF

# Keep the file present but empty: the defaults case supplies values.yaml
# explicitly and the generated-project case supplies only the project values.
: > "$consumer/values.yaml"

run_upgrade() {
  local label="$1"
  shift
  local output="$workdir/${label}.out"

  echo "--- helm upgrade --dry-run: ${label} ---"
  helm upgrade --install "dry-run-${label}" "$consumer" \
    --namespace test-ns \
    --dry-run=client \
    "$@" > "$output"

  if ! grep -q '^kind:' "$output"; then
    echo "test-upgrade-dry-run: ${label} rendered no resources" >&2
    cat "$output" >&2
    exit 1
  fi
  echo "PASS: ${label} upgrade dry-run rendered resources"
}

# The chart's literal defaults have no image repository, so supply the minimum
# required image and tag. The schema validation still covers the full defaults.
run_upgrade chart-defaults \
  -f charts/library/ksvc/values.yaml \
  --set services.api.image.repository=ghcr.io/example-org/ksvc-dry-run \
  --set services.api.image.tag=v1.0.0
run_upgrade generated-managed-kafka \
  -f examples/generated-managed-kafka/values.yaml

echo "--- helm upgrade --dry-run: ksvc-app wrapper ---"
OUTPUT="$workdir/app.out" hack/lint-app.sh bash -c '
  set -euo pipefail
  helm upgrade --install dry-run-app charts/app/ksvc \
    --namespace test-ns \
    --dry-run=client \
    --set services.api.image.repository=ghcr.io/example-org/ksvc-dry-run \
    --set services.api.image.tag=v1.0.0 > "$OUTPUT"
'
if ! grep -q '^kind:' "$workdir/app.out"; then
  echo "test-upgrade-dry-run: ksvc-app rendered no resources" >&2
  cat "$workdir/app.out" >&2
  exit 1
fi
echo "PASS: ksvc-app upgrade dry-run rendered resources"

echo "test-upgrade-dry-run: OK"
