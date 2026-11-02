#!/usr/bin/env bash
#
# test-lock-consistency.sh — prove that the lock-consistency checks reject a
# deliberately stale Chart.lock and accept a consistent one.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "test-lock-consistency: FAIL: $*" >&2
  exit 1
}

# --- Structural check: a stale exact pin must be rejected -------------------
mkdir -p "$tmp/chart"
cat > "$tmp/chart/Chart.yaml" <<'EOF'
apiVersion: v2
name: lock-check-fixture
version: 0.1.0
dependencies:
  - name: ksvc
    version: 1.0.0
    repository: oci://example.invalid/charts
EOF
cat > "$tmp/chart/Chart.lock" <<'EOF'
dependencies:
- name: ksvc
  repository: oci://example.invalid/charts
  version: 0.9.0
digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
generated: "2026-01-01T00:00:00Z"
EOF

if python3 hack/check-chart-lock.py "$tmp/chart" >/dev/null 2>&1; then
  fail "stale exact pin was accepted by check-chart-lock.py"
fi
echo "OK: stale exact pin rejected by check-chart-lock.py"

sed -i 's/version: 0.9.0/version: 1.0.0/' "$tmp/chart/Chart.lock"
python3 hack/check-chart-lock.py "$tmp/chart" >/dev/null
echo "OK: consistent exact pin accepted by check-chart-lock.py"

# --- Helm check: dependency build must reject a stale local lock ------------
mkdir -p "$tmp/dep" "$tmp/parent"
cat > "$tmp/dep/Chart.yaml" <<'EOF'
apiVersion: v2
name: dep
version: 1.0.0
type: library
EOF
cat > "$tmp/parent/Chart.yaml" <<'EOF'
apiVersion: v2
name: parent
version: 0.1.0
dependencies:
  - name: dep
    version: 1.0.0
    repository: file://../dep
EOF
cat > "$tmp/parent/Chart.lock" <<'EOF'
dependencies:
- name: dep
  repository: file://../dep
  version: 0.9.0
digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
generated: "2026-01-01T00:00:00Z"
EOF

if helm dependency build "$tmp/parent" >/dev/null 2>&1; then
  fail "helm dependency build accepted a stale lock"
fi
echo "OK: stale lock rejected by helm dependency build"

helm dependency update "$tmp/parent" >/dev/null
helm dependency build "$tmp/parent" >/dev/null
echo "OK: refreshed lock accepted by helm dependency build"

# --- The repo's own locks are currently consistent --------------------------
for chart in charts/app/ksvc charts/library/ksvc/test-chart examples/*/; do
  [ -f "$chart/Chart.yaml" ] || continue
  python3 hack/check-chart-lock.py "$chart" >/dev/null
done
echo "OK: checked-in Chart.lock files pass the structural check"
