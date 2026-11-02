#!/usr/bin/env bash
#
# test-reconcile-release.sh — scripted dry-run for partial release states.
#
# The real reconcile-release.sh runs against a temporary git repository with
# fake helm and gh executables, so no registry, network, or GitHub API access is
# used. Covered states: missing OCI, missing tag, missing GitHub Release, a tag
# at the wrong commit, and repair mode refusing to publish a new OCI artifact.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "test-reconcile-release: FAIL: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file to exist: $1"
}

assert_no_file() {
  [ ! -f "$1" ] || fail "expected file to be absent: $1"
}

assert_contains() {
  grep -qF "$2" "$1" || {
    echo "--- $1 ---" >&2
    cat "$1" >&2
    fail "expected '$2' in $1"
  }
}

assert_not_contains() {
  if grep -qF "$2" "$1"; then
    echo "--- $1 ---" >&2
    cat "$1" >&2
    fail "did not expect '$2' in $1"
  fi
}

write_fakes() {
  local bin="$1"
  mkdir -p "$bin"

  cat > "$bin/helm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "helm $*" >> "$FAKE_STATE/tools.log"
case "${1:-}" in
  show)
    [ -f "$FAKE_STATE/oci" ]
    ;;
  dependency)
    exit 0
    ;;
  package)
    chart_dir="${2:?}"
    dest="${4:?}"
    name="$(awk '/^name:/{print $2; exit}' "$chart_dir/Chart.yaml")"
    version="$(awk '/^version:/{print $2; exit}' "$chart_dir/Chart.yaml")"
    mkdir -p "$dest"
    : > "$dest/${name}-${version}.tgz"
    ;;
  push)
    : > "$FAKE_STATE/oci"
    ;;
  *)
    echo "fake helm: unexpected command: $*" >&2
    exit 2
    ;;
esac
EOF

  cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gh $*" >> "$FAKE_STATE/tools.log"
case "${1:-} ${2:-}" in
  "release view")
    [ -f "$FAKE_STATE/release" ]
    ;;
  "release create")
    : > "$FAKE_STATE/release"
    ;;
  *)
    echo "fake gh: unexpected command: $*" >&2
    exit 2
    ;;
esac
EOF

  chmod +x "$bin/helm" "$bin/gh"
}

new_repo() {
  local name="$1"
  NEW_BASE="$tmp/$name"
  NEW_REPO="$NEW_BASE/repo"
  NEW_REMOTE="$NEW_BASE/remote.git"
  NEW_STATE="$NEW_BASE/state"
  NEW_BIN="$NEW_BASE/bin"

  mkdir -p "$NEW_REPO/charts/library/ksvc" "$NEW_STATE"
  write_fakes "$NEW_BIN"

  cat > "$NEW_REPO/charts/library/ksvc/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc
type: library
version: 1.0.0
EOF

  git -C "$NEW_REPO" init -q -b main
  git -C "$NEW_REPO" config user.name "Release Test"
  git -C "$NEW_REPO" config user.email "release-test@example.invalid"
  git -C "$NEW_REPO" add charts/library/ksvc/Chart.yaml
  git -C "$NEW_REPO" commit -q -m "test: initial chart"
  NEW_COMMIT="$(git -C "$NEW_REPO" rev-parse HEAD)"

  git init -q --bare "$NEW_REMOTE"
  git -C "$NEW_REPO" remote add origin "$NEW_REMOTE"
  git -C "$NEW_REPO" push -q -u origin main
}

run_reconcile() {
  local extra=("$@")
  set +e
  PATH="$NEW_BIN:$PATH" \
    FAKE_STATE="$NEW_STATE" \
    GITHUB_REPOSITORY="test-org/test-repo" \
    REGISTRY="ghcr.io" \
    bash "$repo_root/hack/release/reconcile-release.sh" \
      --repo-root "$NEW_REPO" \
      --workdir "$NEW_BASE/work" \
      --chart ksvc \
      --version 1.0.0 \
      --path charts/library/ksvc \
      --type library \
      --tag ksvc-v1.0.0 \
      --commit "$NEW_COMMIT" \
      "${extra[@]}" > "$NEW_STATE/run.log" 2>&1
  RC=$?
  set -e
}

push_tag() {
  git -C "$NEW_REPO" tag ksvc-v1.0.0 "$1"
  git -C "$NEW_REPO" push -q origin refs/tags/ksvc-v1.0.0
}

# ---------------------------------------------------------------------------
# 1. OCI missing, tag and GitHub Release already present.
# ---------------------------------------------------------------------------
new_repo missing-oci
push_tag "$NEW_COMMIT"
: > "$NEW_STATE/release"
run_reconcile
[ "$RC" -eq 0 ] || fail "missing OCI scenario exited $RC: $(cat "$NEW_STATE/run.log")"
assert_file "$NEW_STATE/oci"
assert_not_contains "$NEW_STATE/tools.log" "release create"
echo "OK: missing OCI is pushed without recreating tag or Release"

# ---------------------------------------------------------------------------
# 2. OCI and Release present, tag missing.
# ---------------------------------------------------------------------------
new_repo missing-tag
: > "$NEW_STATE/oci"
: > "$NEW_STATE/release"
run_reconcile
[ "$RC" -eq 0 ] || fail "missing tag scenario exited $RC: $(cat "$NEW_STATE/run.log")"
remote_tag="$(git --git-dir="$NEW_REMOTE" rev-parse 'refs/tags/ksvc-v1.0.0^{commit}')"
[ "$remote_tag" = "$NEW_COMMIT" ] || fail "tag was created at $remote_tag, expected $NEW_COMMIT"
assert_not_contains "$NEW_STATE/tools.log" "helm push"
echo "OK: missing tag is created at the expected release commit"

# ---------------------------------------------------------------------------
# 3. OCI and tag present, GitHub Release missing.
# ---------------------------------------------------------------------------
new_repo missing-release
: > "$NEW_STATE/oci"
push_tag "$NEW_COMMIT"
run_reconcile
[ "$RC" -eq 0 ] || fail "missing Release scenario exited $RC: $(cat "$NEW_STATE/run.log")"
assert_file "$NEW_STATE/release"
assert_not_contains "$NEW_STATE/tools.log" "helm push"
echo "OK: missing GitHub Release is created from the expected commit"

# ---------------------------------------------------------------------------
# 4. Tag exists at the wrong commit. Nothing may be mutated.
# ---------------------------------------------------------------------------
new_repo wrong-tag
cat > "$NEW_REPO/charts/library/ksvc/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc
type: library
version: 0.9.0
EOF
git -C "$NEW_REPO" add charts/library/ksvc/Chart.yaml
git -C "$NEW_REPO" commit -q -m "test: previous version"
wrong_commit="$(git -C "$NEW_REPO" rev-parse HEAD)"

cat > "$NEW_REPO/charts/library/ksvc/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc
type: library
version: 1.0.0
EOF
git -C "$NEW_REPO" add charts/library/ksvc/Chart.yaml
git -C "$NEW_REPO" commit -q -m "test: release version"
NEW_COMMIT="$(git -C "$NEW_REPO" rev-parse HEAD)"
git -C "$NEW_REPO" push -q origin main
push_tag "$wrong_commit"

run_reconcile
[ "$RC" -ne 0 ] || fail "wrong-tag scenario unexpectedly succeeded"
assert_contains "$NEW_STATE/run.log" "expected release commit"
assert_no_file "$NEW_STATE/oci"
assert_no_file "$NEW_STATE/release"
echo "OK: tag at the wrong commit fails before any mutation"

# ---------------------------------------------------------------------------
# 5. Repair mode must not publish a new OCI artifact.
# ---------------------------------------------------------------------------
new_repo repair-missing-oci
run_reconcile --repair
[ "$RC" -ne 0 ] || fail "repair mode with missing OCI unexpectedly succeeded"
assert_contains "$NEW_STATE/run.log" "Repair mode requires"
assert_no_file "$NEW_STATE/oci"
assert_not_contains "$NEW_STATE/tools.log" "helm push"
echo "OK: repair mode refuses to publish a missing OCI artifact"

# ---------------------------------------------------------------------------
# 6. Fully reconciled release is a no-op.
# ---------------------------------------------------------------------------
new_repo already-reconciled
: > "$NEW_STATE/oci"
: > "$NEW_STATE/release"
push_tag "$NEW_COMMIT"
run_reconcile
[ "$RC" -eq 0 ] || fail "already-reconciled scenario exited $RC: $(cat "$NEW_STATE/run.log")"
assert_contains "$NEW_STATE/run.log" "Already reconciled"
assert_not_contains "$NEW_STATE/tools.log" "helm package"
echo "OK: fully reconciled release is a no-op"
