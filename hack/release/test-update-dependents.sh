#!/usr/bin/env bash
#
# test-update-dependents.sh — prove the dependent-bump PR updates the released
# dependency and refreshes the app, test-chart, and example locks. Uses a
# temporary git repository and fake make/helm/gh executables.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "test-update-dependents: FAIL: $*" >&2
  exit 1
}

bin="$tmp/bin"
state="$tmp/state"
mkdir -p "$bin" "$state"

cat > "$bin/helm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "helm $*" >> "$FAKE_STATE/helm.log"
if [ "${1:-}" = "dependency" ] && [ "${2:-}" = "build" ]; then
  exit 0
fi
echo "fake helm: unexpected command: $*" >&2
exit 2
EOF

cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gh $*" >> "$FAKE_STATE/gh.log"
if [ "${1:-} ${2:-}" != "pr create" ]; then
  echo "fake gh: unexpected command: $*" >&2
  exit 2
fi
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--body-file" ]; then
    cp "$2" "$FAKE_STATE/pr-body.md"
    shift 2
  else
    shift
  fi
done
if [ -n "${FAKE_GH_FAIL:-}" ]; then
  echo "gh: pull request create failed" >&2
  exit 1
fi
echo "https://github.com/test-org/test-repo/pull/1"
EOF

cat > "$bin/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "make $*" >> "$FAKE_STATE/make.log"
if [ "${1:-}" != "update-locks" ]; then
  echo "fake make: unexpected target: $*" >&2
  exit 2
fi
python3 "$FAKE_STATE/write-locks.py" "$PWD"
EOF
chmod +x "$bin/helm" "$bin/gh" "$bin/make"

cat > "$state/write-locks.py" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])


def chart_version(path: pathlib.Path) -> str:
    for line in path.read_text().splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip().strip('"\'')
    return ""


def local_library_versions() -> dict[str, str]:
    versions: dict[str, str] = {}
    for chart_yaml in root.glob("charts/library/*/Chart.yaml"):
        for line in chart_yaml.read_text().splitlines():
            if line.startswith("name:"):
                versions[line.split(":", 1)[1].strip()] = chart_version(chart_yaml)
                break
    return versions


def dependencies(chart_yaml: pathlib.Path) -> list[dict[str, str]]:
    deps: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    in_deps = False
    for line in chart_yaml.read_text().splitlines():
        if re.match(r"^dependencies:\s*$", line):
            in_deps = True
            continue
        if not in_deps:
            continue
        if re.match(r"^\S", line) and not line.startswith("-"):
            break
        item = re.match(r"^\s*-\s+name:\s*(\S+)\s*$", line)
        if item:
            current = {"name": item.group(1).strip('"\'')}
            deps.append(current)
            continue
        field = re.match(r"^\s+(repository|version):\s*(.+?)\s*$", line)
        if field and current is not None:
            current[field.group(1)] = field.group(2).strip('"\'')
    return deps


local = local_library_versions()
charts: list[pathlib.Path] = []
for pattern in ("charts/app/*", "charts/library/*/test-chart", "examples/*"):
    for chart in root.glob(pattern):
        if (chart / "Chart.yaml").is_file():
            charts.append(chart)

for chart in sorted(set(charts)):
    deps = dependencies(chart / "Chart.yaml")
    if not deps:
        continue
    lines = ["dependencies:"]
    for dep in deps:
        name = dep["name"]
        version = dep.get("version", "")
        if not re.match(r"^\d+\.\d+\.\d+", version):
            version = local.get(name, version)
        lines.extend([
            f"- name: {name}",
            f"  repository: {dep.get('repository', '')}",
            f"  version: {version}",
        ])
    lines.extend([
        "digest: sha256:0000000000000000000000000000000000000000000000000000000000000000",
        'generated: "2026-01-01T00:00:00Z"',
    ])
    (chart / "Chart.lock").write_text("\n".join(lines) + "\n")
PY

new_repo() {
  local name="$1"
  REPO="$tmp/$name/repo"
  REMOTE="$tmp/$name/remote.git"
  WORK_STATE="$tmp/$name/state"
  mkdir -p "$REPO/charts/library/ksvc/test-chart" "$REPO/charts/app/ksvc" \
    "$REPO/examples/minimal" "$REPO/hack/release" "$WORK_STATE"
  cp "$repo_root/hack/check-chart-lock.py" "$REPO/hack/check-chart-lock.py"
  cp "$state/write-locks.py" "$WORK_STATE/write-locks.py"

  cat > "$REPO/charts/library/ksvc/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc
type: library
version: 1.0.0
EOF

  cat > "$REPO/charts/app/ksvc/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc-app
type: application
version: 0.7.4
dependencies:
  - name: ksvc
    version: 0.10.0
    repository: oci://ghcr.io/test-org/charts
EOF

  cat > "$REPO/charts/library/ksvc/test-chart/Chart.yaml" <<'EOF'
apiVersion: v2
name: ksvc-test
type: application
version: 0.0.1
dependencies:
  - name: ksvc
    repository: file://..
    version: ">0.0.0-0"
EOF

  cat > "$REPO/examples/minimal/Chart.yaml" <<'EOF'
apiVersion: v2
name: minimal-example
type: application
version: 0.1.0
dependencies:
  - name: ksvc
    repository: "file://../../charts/library/ksvc"
    version: ">=0.1.0-0"
EOF

  cat > "$REPO/charts/app/ksvc/Chart.lock" <<'EOF'
dependencies:
- name: ksvc
  repository: oci://ghcr.io/test-org/charts
  version: 0.10.0
digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
generated: "2026-01-01T00:00:00Z"
EOF
  cp "$REPO/charts/app/ksvc/Chart.lock" "$REPO/charts/library/ksvc/test-chart/Chart.lock"
  cp "$REPO/charts/app/ksvc/Chart.lock" "$REPO/examples/minimal/Chart.lock"

  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.name "Release Test"
  git -C "$REPO" config user.email "release-test@example.invalid"
  git -C "$REPO" add .
  git -C "$REPO" commit -q -m "test: initial charts"
  git init -q --bare "$REMOTE"
  git -C "$REPO" remote add origin "$REMOTE"
  git -C "$REPO" push -q -u origin main
}

run_update() {
  local matrix="$1" extra=("${@:2}")
  set +e
  PATH="$bin:$PATH" FAKE_STATE="$WORK_STATE" \
    GITHUB_REPOSITORY="test-org/test-repo" \
    RELEASED_MATRIX="$matrix" \
    bash "$repo_root/hack/release/update-dependents.sh" \
      --repo-root "$REPO" \
      --release-commit "$(git -C "$REPO" rev-parse HEAD)" \
      --branch-name "chore/bump-deps-test" \
      "${extra[@]}" > "$WORK_STATE/stdout" 2> "$WORK_STATE/stderr"
  rc=$?
  set -e
}

matrix='{"include":[{"name":"ksvc","version":"1.0.0","type":"library","path":"charts/library/ksvc","tag":"ksvc-v1.0.0","commit":"deadbeef","repair":"false"}]}'

# --- Tag-triggered library release bumps the app and refreshes all locks ----
new_repo bump
git -C "$REPO" tag ksvc-v1.0.0
run_update "$matrix"
[ "$rc" -eq 0 ] || fail "dependent bump exited $rc: $(cat "$WORK_STATE/stderr")"

grep -q '^version: 0.7.5$' "$REPO/charts/app/ksvc/Chart.yaml" \
  || fail "app chart patch version was not bumped"
grep -q '^    version: 1.0.0$' "$REPO/charts/app/ksvc/Chart.yaml" \
  || fail "app chart dependency was not bumped to the released version"
for lock in \
  "$REPO/charts/app/ksvc/Chart.lock" \
  "$REPO/charts/library/ksvc/test-chart/Chart.lock" \
  "$REPO/examples/minimal/Chart.lock"; do
  grep -q 'version: 1.0.0' "$lock" || fail "$lock was not refreshed to 1.0.0"
done
[ -f "$WORK_STATE/pr-body.md" ] || fail "gh pr create did not receive a body file"
grep -q 'ksvc.*1.0.0' "$WORK_STATE/pr-body.md" || fail "PR body does not list the released version"
grep -q 'charts/library/ksvc/test-chart/Chart.lock' "$WORK_STATE/pr-body.md" \
  || fail "PR body does not list the test-chart lock"
grep -q 'make update-locks' "$WORK_STATE/make.log" || fail "make update-locks was not used"
grep -q 'pr create' "$WORK_STATE/gh.log" || fail "dependent PR was not opened"
[ -n "$(git --git-dir="$REMOTE" branch --list 'chore/bump-deps-test')" ] \
  || fail "dependent bump branch was not pushed"
echo "OK: tag-triggered library release opens one PR with the app bump and all refreshed locks"

# --- The release commit must be the checkout HEAD (tag wiring) --------------
new_repo wrong-commit
git -C "$REPO" commit -q --allow-empty -m "test: later main commit"
old_commit="$(git -C "$REPO" rev-parse HEAD^)"
set +e
PATH="$bin:$PATH" FAKE_STATE="$WORK_STATE" \
  GITHUB_REPOSITORY="test-org/test-repo" RELEASED_MATRIX="$matrix" \
  bash "$repo_root/hack/release/update-dependents.sh" \
    --repo-root "$REPO" --release-commit "$old_commit" \
    --branch-name "chore/bump-deps-test" > "$WORK_STATE/stdout" 2> "$WORK_STATE/stderr"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "update-dependents accepted a checkout that was not the release commit"
grep -q 'checkout is' "$WORK_STATE/stderr" || fail "missing wrong-commit error message"
echo "OK: tag releases must check out the tagged release commit"

# --- A failure to open the PR is a clear failure ----------------------------
new_repo pr-failure
set +e
PATH="$bin:$PATH" FAKE_STATE="$WORK_STATE" FAKE_GH_FAIL=1 \
  GITHUB_REPOSITORY="test-org/test-repo" RELEASED_MATRIX="$matrix" \
  bash "$repo_root/hack/release/update-dependents.sh" \
    --repo-root "$REPO" --release-commit "$(git -C "$REPO" rev-parse HEAD)" \
    --branch-name "chore/bump-deps-test" > "$WORK_STATE/stdout" 2> "$WORK_STATE/stderr"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "PR creation failure was swallowed"
grep -q 'opening the PR failed' "$WORK_STATE/stderr" || fail "missing clear PR failure message"
echo "OK: a dependent PR that cannot be opened fails with actionable context"

# --- An application-only release skips dependent bumps ---------------------
new_repo app-only
matrix_app='{"include":[{"name":"ksvc-app","version":"0.7.5","type":"application","path":"charts/app/ksvc","tag":"ksvc-app-v0.7.5","commit":"deadbeef","repair":"false"}]}'
run_update "$matrix_app"
[ "$rc" -eq 0 ] || fail "application-only release exited $rc: $(cat "$WORK_STATE/stderr")"
grep -q 'No library charts in the release matrix' "$WORK_STATE/stdout" \
  || fail "application-only release did not explain the skip"
grep -q 'pr create' "$WORK_STATE/gh.log" 2>/dev/null \
  && fail "application-only release opened a dependent PR"
echo "OK: application-only releases do not bump dependents"

echo "All update-dependents tests passed."
