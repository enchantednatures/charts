#!/usr/bin/env bash
#
# test-release-gate.sh — exercise the release gate against Checks API fixtures.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "test-release-gate: FAIL: $*" >&2
  exit 1
}

required=(
  "Helm Lint"
  "Schema Validation"
  "Template Rendering"
  "Helm Unit Tests"
  "Kubernetes Schema Validation"
  "Kind Cluster Deploy"
  "App Chart Dry-Run"
  "Kyverno Guardrails E2E"
  "Kafka Strimzi E2E"
)

names_json="$(jq -cn --args '$ARGS.positional' \
  "Helm Lint (v3.17.0)" \
  "Helm Lint (v4.3.0)" \
  "Schema Validation" \
  "Template Rendering (v3.17.0)" \
  "Template Rendering (v4.3.0)" \
  "Helm Unit Tests (v3.17.0)" \
  "Helm Unit Tests (v4.3.0)" \
  "Kubernetes Schema Validation (1.28.0)" \
  "Kubernetes Schema Validation (1.30.0)" \
  "Kubernetes Schema Validation (1.32.0)" \
  "Kind Cluster Deploy (minimal)" \
  "Kind Cluster Deploy (full-stack)" \
  "App Chart Dry-Run" \
  "Kyverno Guardrails E2E" \
  "Kafka Strimzi E2E")"

make_fixture() {
  local path="$1"
  jq -n --argjson names "$names_json" '{
    total_count: ($names | length),
    check_runs: [$names[] | {id: 1, name: ., status: "completed", conclusion: "success"}]
  }' > "$path"
}

all_success="$tmp/all-success.json"
make_fixture "$all_success"

hack/release/check-required-checks.sh --commit deadbeef --check-runs-json "$all_success" >/dev/null
echo "OK: all required matrix checks pass"

missing="$tmp/missing.json"
jq 'del(.check_runs[] | select(.name == "Schema Validation"))' "$all_success" > "$missing"
if hack/release/check-required-checks.sh --commit deadbeef --check-runs-json "$missing" >/dev/null 2>&1; then
  fail "missing required check was accepted"
fi
echo "OK: missing required check is rejected"

failed="$tmp/failed.json"
jq '(.check_runs[] | select(.name == "Kafka Strimzi E2E") | .conclusion) = "failure"' \
  "$all_success" > "$failed"
if hack/release/check-required-checks.sh --commit deadbeef --check-runs-json "$failed" >/dev/null 2>&1; then
  fail "failed required check was accepted"
fi
echo "OK: failed required check is rejected"

pending="$tmp/pending.json"
jq '(.check_runs[] | select(.name == "App Chart Dry-Run") | .status) = "in_progress"' \
  "$all_success" > "$pending"
if hack/release/check-required-checks.sh --commit deadbeef --check-runs-json "$pending" >/dev/null 2>&1; then
  fail "pending required check was accepted"
fi
echo "OK: pending required check is rejected"

rerun="$tmp/rerun.json"
jq '.check_runs += [
  {id: 10, name: "Schema Validation", status: "completed", conclusion: "failure"},
  {id: 11, name: "Schema Validation", status: "completed", conclusion: "success"}
]' "$all_success" > "$rerun"
hack/release/check-required-checks.sh --commit deadbeef --check-runs-json "$rerun" >/dev/null
echo "OK: newest re-run result wins"
