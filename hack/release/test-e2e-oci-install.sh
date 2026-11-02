#!/usr/bin/env bash
#
# test-e2e-oci-install.sh — exercise the post-publish e2e control flow with
# fake helm/kubectl/curl executables. No cluster, registry, or network access
# is used.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "test-e2e-oci-install: FAIL: $*" >&2
  exit 1
}

bin="$tmp/bin"
state="$tmp/state"
mkdir -p "$bin" "$state"

cat > "$bin/helm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "helm $*" >> "$FAKE_STATE/helm.log"

namespace="default"
chart_version=""
image_repository=""
image_tag=""

parse_options() {
  local args=("$@")
  local index=0
  while [ "$index" -lt "${#args[@]}" ]; do
    case "${args[$index]}" in
      --namespace) namespace="${args[$((index + 1))]}"; index=$((index + 2)) ;;
      --version) chart_version="${args[$((index + 1))]}"; index=$((index + 2)) ;;
      --set-string)
        case "${args[$((index + 1))]}" in
          services.api.image.repository=*) image_repository="${args[$((index + 1))]#*=}" ;;
          services.api.image.tag=*) image_tag="${args[$((index + 1))]#*=}" ;;
        esac
        index=$((index + 2))
        ;;
      *) index=$((index + 1)) ;;
    esac
  done
}

case "${1:-}" in
  show)
    exit 0
    ;;
  dependency)
    chart_dir="${3:?missing chart dir}"
    dep_version="$(awk '
      /- name: ksvc/ { found = 1; next }
      found && /version:/ { sub(/^[[:space:]]*version:[[:space:]]*/, ""); print; exit }
    ' "$chart_dir/Chart.yaml")"
    cat > "$chart_dir/Chart.lock" <<LOCK
dependencies:
- name: ksvc
  repository: oci://fake
  version: ${dep_version}
LOCK
    ;;
  install)
    release="$2"
    parse_options "${@:3}"
    printf '1\n' > "$FAKE_STATE/revision"
    printf '%s\n' "$chart_version" > "$FAKE_STATE/chart-version"
    printf '%s\n' "${image_repository}:${image_tag}" > "$FAKE_STATE/initial-image"
    printf '%s\n' "${image_repository}:${image_tag}" > "$FAKE_STATE/image"
    printf '%s\n' "$release" > "$FAKE_STATE/release"
    cp "$FAKE_STATE/image" "$FAKE_STATE/kservice"
    ;;
  upgrade)
    parse_options "${@:3}"
    revision="$(cat "$FAKE_STATE/revision")"
    printf '%s\n' "$((revision + 1))" > "$FAKE_STATE/revision"
    printf '%s\n' "$chart_version" > "$FAKE_STATE/chart-version"
    printf '%s\n' "${image_repository}:${image_tag}" > "$FAKE_STATE/image"
    cp "$FAKE_STATE/image" "$FAKE_STATE/kservice"
    ;;
  rollback)
    revision="$(cat "$FAKE_STATE/revision")"
    printf '%s\n' "$((revision + 1))" > "$FAKE_STATE/revision"
    cp "$FAKE_STATE/initial-image" "$FAKE_STATE/image"
    cp "$FAKE_STATE/image" "$FAKE_STATE/kservice"
    ;;
  status)
    if [ ! -f "$FAKE_STATE/release" ]; then
      echo "release: not found" >&2
      exit 1
    fi
    python3 - "$FAKE_STATE" <<'PY'
import json
import pathlib
import sys

state = pathlib.Path(sys.argv[1])
print(json.dumps({
    "name": (state / "release").read_text().strip(),
    "version": int((state / "revision").read_text().strip()),
    "chart": {"metadata": {"version": (state / "chart-version").read_text().strip()}},
}))
PY
    ;;
  uninstall)
    rm -f "$FAKE_STATE/release" "$FAKE_STATE/revision" \
      "$FAKE_STATE/chart-version" "$FAKE_STATE/initial-image" "$FAKE_STATE/image"
    if [ -z "${FAKE_KEEP_KSERVICE:-}" ]; then
      rm -f "$FAKE_STATE/kservice"
    fi
    ;;
  *)
    echo "fake helm: unexpected command: $*" >&2
    exit 2
    ;;
esac
EOF

cat > "$bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "kubectl $*" >> "$FAKE_STATE/kubectl.log"

if [ "${1:-}" = "delete" ]; then
  rm -f "$FAKE_STATE/kservice"
  exit 0
fi

if [ "${1:-}" = "get" ] && [ "${2:-}" = "kservice" ]; then
  if [ -f "$FAKE_STATE/kservice" ]; then
    cat "$FAKE_STATE/kservice"
    exit 0
  fi
  exit 1
fi

echo "fake kubectl: unexpected command: $*" >&2
exit 2
EOF

cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "curl $*" >> "$FAKE_STATE/curl.log"
case "$*" in
  *"/token"*) printf '%s\n' '{"token":"fake-token"}' ;;
  *"/tags/list"*) cat "$FAKE_STATE/tags.json" ;;
  *) echo "fake curl: unexpected request: $*" >&2; exit 2 ;;
esac
EOF

chmod +x "$bin/helm" "$bin/kubectl" "$bin/curl"

run_e2e() {
  set +e
  PATH="$bin:$PATH" FAKE_STATE="$state" \
    bash hack/release/e2e-oci-install.sh \
      --oci-repository oci://ghcr.io/test-org/charts \
      --release-name release-e2e \
      --namespace release-e2e \
      --workdir "$tmp/work" \
      "$@" > "$state/stdout" 2> "$state/stderr"
  rc=$?
  set -e
}

reset_state() {
  rm -rf "$state"
  mkdir -p "$state"
  : > "$state/helm.log"
  : > "$state/kubectl.log"
  : > "$state/curl.log"
}

# --- Direct consumer: previous install, upgrade, rollback, uninstall --------
reset_state
run_e2e --chart ksvc --version 1.0.0 --chart-type library --previous-version 0.10.0
[ "$rc" -eq 0 ] || fail "consumer e2e exited $rc: $(cat "$state/stderr")"
grep -q "install release-e2e $tmp/work/consumer-previous" "$state/helm.log" \
  || fail "consumer e2e did not install the previous consumer chart from OCI"
grep -q "upgrade release-e2e $tmp/work/consumer-current" "$state/helm.log" \
  || fail "consumer e2e did not upgrade to the released consumer chart"
grep -q "rollback release-e2e 1" "$state/helm.log" || fail "consumer e2e did not roll back"
grep -q "uninstall release-e2e" "$state/helm.log" || fail "consumer e2e did not uninstall"
grep -q "Post-publish OCI e2e passed for ksvc v1.0.0" "$state/stdout" \
  || fail "consumer e2e did not report success"
[ ! -f "$state/kservice" ] || fail "consumer e2e left the Knative Service behind"
echo "OK: library release installs a consumer chart from OCI, upgrades, rolls back, and uninstalls"

# --- Application chart: the published chart version is asserted -------------
reset_state
run_e2e --chart ksvc-app --version 0.7.4 --chart-type application --previous-version 0.7.3
[ "$rc" -eq 0 ] || fail "app e2e exited $rc: $(cat "$state/stderr")"
grep -q -- "--version 0.7.3" "$state/helm.log" || fail "app e2e did not install N-1"
grep -q -- "--version 0.7.4" "$state/helm.log" || fail "app e2e did not upgrade to the release"
grep -q "Installed chart version is 0.7.3" "$state/stdout" || fail "app e2e did not verify N-1 chart version"
grep -q "Installed chart version is 0.7.4" "$state/stdout" || fail "app e2e did not verify released chart version"
echo "OK: application release installs the published chart by version, upgrades, and rolls back"

# --- No previous version: explicit notice, install-only smoke --------------
reset_state
run_e2e --chart ksvc --version 1.0.0 --chart-type library --previous-version ""
[ "$rc" -eq 0 ] || fail "first-release e2e exited $rc: $(cat "$state/stderr")"
grep -q "::notice::No previous published version" "$state/stdout" \
  || fail "first-release e2e did not emit the skip annotation"
if grep -q "upgrade release-e2e" "$state/helm.log"; then
  fail "first-release e2e attempted an upgrade without N-1"
fi
grep -q "install release-e2e" "$state/helm.log" || fail "first-release e2e did not smoke install"
grep -q "uninstall release-e2e" "$state/helm.log" || fail "first-release e2e did not uninstall"
echo "OK: first-ever release skips upgrade/rollback with a notice but still installs and uninstalls"

# --- Discovery runs when no previous version is supplied -------------------
reset_state
printf '%s\n' '{"tags":["1.0.0-rc.1.2","1.0.0-rc.1.3","0.10.0"]}' > "$state/tags.json"
run_e2e --chart ksvc --version 1.0.0-rc.1.3 --chart-type library
[ "$rc" -eq 0 ] || fail "discovery e2e exited $rc: $(cat "$state/stderr")"
grep -q "Discovering the previous published version" "$state/stdout" \
  || fail "e2e did not attempt previous-version discovery"
grep -q "Installing previous published version 1.0.0-rc.1.2" "$state/stdout" \
  || fail "e2e did not use the discovered previous version"
grep -q "tags/list" "$state/curl.log" || fail "e2e did not query the registry tag list"
echo "OK: e2e discovers N-1 from the registry when it is not supplied"

# --- A leftover resource fails the cleanup assertion -----------------------
reset_state
set +e
PATH="$bin:$PATH" FAKE_STATE="$state" FAKE_KEEP_KSERVICE=1 \
  bash hack/release/e2e-oci-install.sh \
    --oci-repository oci://ghcr.io/test-org/charts \
    --release-name release-e2e \
    --namespace release-e2e \
    --workdir "$tmp/work" \
    --chart ksvc --version 1.0.0 --chart-type library --previous-version 0.10.0 \
    > "$state/stdout" 2> "$state/stderr"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "leftover Knative Service was accepted"
grep -q "still exists after uninstall" "$state/stderr" || fail "missing cleanup failure message"
echo "OK: uninstall cleanup is asserted"

echo "All e2e-oci-install tests passed."
