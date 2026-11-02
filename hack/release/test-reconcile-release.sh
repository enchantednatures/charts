#!/usr/bin/env bash
#
# test-reconcile-release.sh — scripted dry-run for partial release states.
#
# The real reconcile-release.sh runs against a temporary git repository with
# fake helm and gh executables, so no registry, network, or GitHub API access is
# used. Covered states: missing OCI, missing tag, missing GitHub Release, a tag
# at the wrong commit, repair mode refusing to publish a new OCI artifact,
# application charts waiting for and validating their ksvc dependency, and
# prerelease versus stable GitHub Release creation flags.
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
  grep -qF -- "$2" "$1" || {
    echo "--- $1 ---" >&2
    cat "$1" >&2
    fail "expected '$2' in $1"
  }
}

assert_not_contains() {
  if grep -qF -- "$2" "$1"; then
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
    ref="${3:-}"
    case "$ref" in
      */ksvc)
        if [ -f "$FAKE_STATE/oci" ] || [ -f "$FAKE_STATE/dep-oci" ]; then
          exit 0
        fi
        if [ -n "${FAKE_DEP_APPEAR_AFTER:-}" ]; then
          count_file="$FAKE_STATE/dep-show-count"
          count=0
          [ -f "$count_file" ] && count="$(cat "$count_file")"
          count=$((count + 1))
          echo "$count" > "$count_file"
          if [ "$count" -ge "$FAKE_DEP_APPEAR_AFTER" ]; then
            : > "$FAKE_STATE/dep-oci"
            exit 0
          fi
        fi
        exit 1
        ;;
      *)
        [ -f "$FAKE_STATE/oci" ]
        ;;
    esac
    ;;
  dependency)
    exit 0
    ;;
  package)
    chart_dir="${2:?}"
    dest="${4:?}"
    name="$(awk '/^name:/{print $2; exit}' "$chart_dir/Chart.yaml")"
    version="$(awk '/^version:/{print $2; exit}' "$chart_dir/Chart.yaml")"
    staging="$FAKE_STATE/package-root"
    rm -rf "$staging"
    mkdir -p "$staging/$name" "$dest"
    cp "$chart_dir/Chart.yaml" "$staging/$name/Chart.yaml"
    if [ -f "$FAKE_STATE/packaged-zero-indent-deps" ]; then
      sed -i '/^dependencies:/,/^[^[:space:]]/ s/^  //' "$staging/$name/Chart.yaml"
    fi
    if [ -f "$FAKE_STATE/packaged-dependency-version" ]; then
      pinned="$(cat "$FAKE_STATE/packaged-dependency-version")"
      sed -i "s/^\\([[:space:]]*version:\\).*/\\1 ${pinned}/" "$staging/$name/Chart.yaml"
    fi
    tar -C "$staging" -czf "$dest/${name}-${version}.tgz" "$name"
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

  mkdir -p "$NEW_REPO/charts/library/ksvc" "$NEW_REPO/charts/app/ksvc" "$NEW_STATE"
  write_fakes "$NEW_BIN"

  cat > "$NEW_REPO/charts/library/ksvc/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc
type: library
version: 1.0.0
EOF

  cat > "$NEW_REPO/charts/app/ksvc/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc-app
type: application
version: 0.7.3
dependencies:
  - name: ksvc
    version: 1.0.0
    repository: oci://ghcr.io/test-org/charts
EOF

  git -C "$NEW_REPO" init -q -b main
  git -C "$NEW_REPO" config user.name "Release Test"
  git -C "$NEW_REPO" config user.email "release-test@example.invalid"
  git -C "$NEW_REPO" add charts/library/ksvc/Chart.yaml charts/app/ksvc/Chart.yaml
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

run_reconcile_app() {
  local extra=("$@")
  set +e
  PATH="$NEW_BIN:$PATH" \
    FAKE_STATE="$NEW_STATE" \
    FAKE_DEP_APPEAR_AFTER="${FAKE_DEP_APPEAR_AFTER:-}" \
    GITHUB_REPOSITORY="test-org/test-repo" \
    REGISTRY="ghcr.io" \
    DEPENDENCY_WAIT_ATTEMPTS="${DEPENDENCY_WAIT_ATTEMPTS:-60}" \
    DEPENDENCY_WAIT_INTERVAL_SECONDS="${DEPENDENCY_WAIT_INTERVAL_SECONDS:-10}" \
    bash "$repo_root/hack/release/reconcile-release.sh" \
      --repo-root "$NEW_REPO" \
      --workdir "$NEW_BASE/work" \
      --chart ksvc-app \
      --version 0.7.3 \
      --path charts/app/ksvc \
      --type application \
      --tag ksvc-app-v0.7.3 \
      --commit "$NEW_COMMIT" \
      "${extra[@]}" > "$NEW_STATE/run.log" 2>&1
  RC=$?
  set -e
}

run_reconcile_prerelease() {
  set +e
  PATH="$NEW_BIN:$PATH" \
    FAKE_STATE="$NEW_STATE" \
    GITHUB_REPOSITORY="test-org/test-repo" \
    REGISTRY="ghcr.io" \
    bash "$repo_root/hack/release/reconcile-release.sh" \
      --repo-root "$NEW_REPO" \
      --workdir "$NEW_BASE/work" \
      --chart ksvc \
      --version 1.0.0-rc.1 \
      --path charts/library/ksvc \
      --type library \
      --tag ksvc-v1.0.0-rc.1 \
      --commit "$NEW_COMMIT" \
      "$@" > "$NEW_STATE/run.log" 2>&1
  RC=$?
  set -e
}

push_tag() {
  local tag="${2:-ksvc-v1.0.0}"
  git -C "$NEW_REPO" tag "$tag" "$1"
  git -C "$NEW_REPO" push -q origin "refs/tags/$tag"
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
assert_not_contains "$NEW_STATE/tools.log" "--prerelease"
assert_not_contains "$NEW_STATE/tools.log" "--latest=false"
echo "OK: missing GitHub Release is created from the expected commit as a stable release"

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

# ---------------------------------------------------------------------------
# 7. Application chart dependency is already available: packages immediately.
# ---------------------------------------------------------------------------
new_repo app-dependency-available
: > "$NEW_STATE/dep-oci"
: > "$NEW_STATE/packaged-zero-indent-deps"
run_reconcile_app
[ "$RC" -eq 0 ] || fail "app dependency-available scenario exited $RC: $(cat "$NEW_STATE/run.log")"
assert_file "$NEW_STATE/oci"
assert_contains "$NEW_STATE/tools.log" "show chart oci://ghcr.io/test-org/charts/ksvc --version 1.0.0"
assert_contains "$NEW_STATE/tools.log" "helm dependency build charts/app/ksvc"
assert_contains "$NEW_STATE/tools.log" "helm package charts/app/ksvc"
assert_contains "$NEW_STATE/run.log" "Packaged ksvc-app pins ksvc v1.0.0"
echo "OK: application chart packages when its ksvc dependency is already published"

# ---------------------------------------------------------------------------
# 8. Application chart dependency appears after a retry: still packages.
# ---------------------------------------------------------------------------
new_repo app-dependency-retry
: > "$NEW_STATE/packaged-zero-indent-deps"
FAKE_DEP_APPEAR_AFTER=3 DEPENDENCY_WAIT_ATTEMPTS=5 DEPENDENCY_WAIT_INTERVAL_SECONDS=0 run_reconcile_app
[ "$RC" -eq 0 ] || fail "app dependency-retry scenario exited $RC: $(cat "$NEW_STATE/run.log")"
assert_file "$NEW_STATE/dep-oci"
assert_file "$NEW_STATE/oci"
dep_shows="$(grep -c 'show chart oci://ghcr.io/test-org/charts/ksvc --version 1.0.0' "$NEW_STATE/tools.log" || true)"
[ "$dep_shows" -ge 3 ] || fail "expected at least 3 dependency checks, saw $dep_shows"
echo "OK: application chart wait retries until the ksvc dependency is published"

# ---------------------------------------------------------------------------
# 9. Packaged application chart pins a different dependency version: fails.
# ---------------------------------------------------------------------------
new_repo app-dependency-mismatch
: > "$NEW_STATE/dep-oci"
: > "$NEW_STATE/packaged-zero-indent-deps"
echo "9.9.9" > "$NEW_STATE/packaged-dependency-version"
run_reconcile_app
[ "$RC" -ne 0 ] || fail "packaged dependency mismatch unexpectedly succeeded"
assert_contains "$NEW_STATE/run.log" "Packaged ksvc-app asset pins ksvc v9.9.9"
assert_contains "$NEW_STATE/run.log" "expects v1.0.0"
assert_no_file "$NEW_STATE/oci"
assert_not_contains "$NEW_STATE/tools.log" "helm push"
echo "OK: packaged application chart with the wrong dependency version is rejected"

# ---------------------------------------------------------------------------
# 10. Application chart dependency never appears: fails with a clear timeout.
# ---------------------------------------------------------------------------
new_repo app-dependency-timeout
DEPENDENCY_WAIT_ATTEMPTS=2 DEPENDENCY_WAIT_INTERVAL_SECONDS=0 run_reconcile_app
[ "$RC" -ne 0 ] || fail "missing app dependency unexpectedly succeeded"
assert_contains "$NEW_STATE/run.log" "Application chart ksvc-app requires ksvc v1.0.0"
assert_contains "$NEW_STATE/run.log" "after 2 attempts"
assert_no_file "$NEW_STATE/oci"
assert_not_contains "$NEW_STATE/tools.log" "helm package"
echo "OK: application chart fails clearly when the ksvc dependency never appears"

# ---------------------------------------------------------------------------
# 11. Semver prerelease versions create a prerelease GitHub Release.
# ---------------------------------------------------------------------------
new_repo prerelease-release
cat > "$NEW_REPO/charts/library/ksvc/Chart.yaml" <<'CHART'
apiVersion: v2
name: ksvc
type: library
version: 1.0.0-rc.1
CHART
git -C "$NEW_REPO" add charts/library/ksvc/Chart.yaml
git -C "$NEW_REPO" commit -q -m "test: prerelease version"
git -C "$NEW_REPO" push -q origin main
NEW_COMMIT="$(git -C "$NEW_REPO" rev-parse HEAD)"

: > "$NEW_STATE/oci"
run_reconcile_prerelease
[ "$RC" -eq 0 ] || fail "prerelease scenario exited $RC: $(cat "$NEW_STATE/run.log")"
assert_file "$NEW_STATE/release"
assert_contains "$NEW_STATE/tools.log" "gh release create ksvc-v1.0.0-rc.1"
assert_contains "$NEW_STATE/tools.log" "--prerelease"
assert_contains "$NEW_STATE/tools.log" "--latest=false"
remote_tag="$(git --git-dir="$NEW_REMOTE" rev-parse 'refs/tags/ksvc-v1.0.0-rc.1^{commit}')"
[ "$remote_tag" = "$NEW_COMMIT" ] || fail "prerelease tag was created at $remote_tag, expected $NEW_COMMIT"
echo "OK: prerelease version creates a prerelease GitHub Release with --latest=false"
