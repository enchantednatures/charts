#!/usr/bin/env bash
#
# test-sign-release.sh — exercise sign-release.sh with fake release tooling.
#
# Covers digest derivation, SPDX SBOM generation, signature/SBOM/attestation
# command wiring, GitHub Release upload, and fail-closed behavior when Syft or
# cosign attest fails. No registry, OIDC, or GitHub API access is used.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "test-sign-release: FAIL: $*" >&2
  exit 1
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

  cat > "$bin/cosign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "cosign $*" >> "$FAKE_STATE/tools.log"
case "${1:-}" in
  triangulate)
    echo "ghcr.io/test-org/charts/ksvc:sha256-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef.sig"
    ;;
  sign|attach|attest)
    if [ "${FAKE_FAIL:-}" = "$1" ]; then
      echo "fake cosign: forced failure for $1" >&2
      exit 1
    fi
    ;;
  *)
    echo "fake cosign: unexpected command: $*" >&2
    exit 2
    ;;
esac
EOF

  cat > "$bin/helm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "helm $*" >> "$FAKE_STATE/tools.log"
case "${1:-}" in
  pull)
    dest=""
    version=""
    shift
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --version) version="$2"; shift 2 ;;
        --destination) dest="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -n "$dest" ] && [ -n "$version" ] || exit 2
    staging="$FAKE_STATE/chart"
    rm -rf "$staging"
    mkdir -p "$staging/ksvc"
    printf 'apiVersion: v2\nname: ksvc\nversion: %s\n' "$version" > "$staging/ksvc/Chart.yaml"
    tar -C "$staging" -czf "$dest/ksvc-${version}.tgz" ksvc
    ;;
  *)
    echo "fake helm: unexpected command: $*" >&2
    exit 2
    ;;
esac
EOF

  cat > "$bin/syft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "syft $*" >> "$FAKE_STATE/tools.log"
if [ "${FAKE_FAIL:-}" = "syft" ]; then
  echo "fake syft: forced failure" >&2
  exit 1
fi
out=""
for arg in "$@"; do
  case "$arg" in
    spdx-json=*) out="${arg#spdx-json=}" ;;
  esac
done
[ -n "$out" ] || exit 2
mkdir -p "$(dirname "$out")"
printf '{"spdxVersion":"SPDX-2.3","packages":[{"name":"ksvc"}]}\n' > "$out"
EOF

  cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gh $*" >> "$FAKE_STATE/tools.log"
case "${1:-} ${2:-}" in
  "release upload") ;;
  *)
    echo "fake gh: unexpected command: $*" >&2
    exit 2
    ;;
esac
EOF

  chmod +x "$bin/cosign" "$bin/helm" "$bin/syft" "$bin/gh"
}

new_state() {
  NEW_STATE="$tmp/$1"
  NEW_BIN="$NEW_STATE/bin"
  mkdir -p "$NEW_STATE"
  write_fakes "$NEW_BIN"
}

run_sign() {
  set +e
  PATH="$NEW_BIN:$PATH" \
    FAKE_STATE="$NEW_STATE" \
    FAKE_FAIL="${FAKE_FAIL:-}" \
    GITHUB_REPOSITORY="test-org/test-repo" \
    REGISTRY="ghcr.io" \
    GITHUB_WORKFLOW_REF="test-org/test-repo/.github/workflows/release.yaml@refs/heads/main" \
    GITHUB_SERVER_URL="https://github.com" \
    GITHUB_RUN_ID="12345" \
    GITHUB_REF="refs/heads/main" \
    bash "$repo_root/hack/release/sign-release.sh" \
      --chart ksvc \
      --version "$(grep '^version:' charts/library/ksvc/Chart.yaml | head -1 | awk '{print $2}')" \
      --path charts/library/ksvc \
      --tag "ksvc-v$(grep '^version:' charts/library/ksvc/Chart.yaml | head -1 | awk '{print $2}')" \
      --commit "$(git rev-parse HEAD)" \
      --workdir "$NEW_STATE/work" > "$NEW_STATE/run.log" 2>&1
  RC=$?
  set -e
}

digest="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
version="$(grep '^version:' charts/library/ksvc/Chart.yaml | head -1 | awk '{print $2}')"

# ---------------------------------------------------------------------------
# 1. Successful signing, SBOM attachment, attestation, and release upload.
# ---------------------------------------------------------------------------
new_state success
run_sign
[ "$RC" -eq 0 ] || fail "success scenario exited $RC: $(cat "$NEW_STATE/run.log")"
assert_contains "$NEW_STATE/tools.log" "cosign sign --yes ghcr.io/test-org/charts/ksvc:${version}"
assert_contains "$NEW_STATE/tools.log" "cosign attach sbom --sbom"
assert_contains "$NEW_STATE/tools.log" "--type spdxjson ghcr.io/test-org/charts/ksvc@sha256:${digest}"
assert_contains "$NEW_STATE/tools.log" "cosign attest --yes --predicate"
assert_contains "$NEW_STATE/tools.log" "--type slsaprovenance1 ghcr.io/test-org/charts/ksvc@sha256:${digest}"
assert_contains "$NEW_STATE/tools.log" "gh release upload ksvc-v${version}"
assert_contains "$NEW_STATE/tools.log" "--repo test-org/test-repo --clobber"

predicate="$NEW_STATE/work/ksvc-${version}.provenance.json"
[ -f "$predicate" ] || fail "provenance predicate was not written"
[ "$(jq -r '.buildDefinition.externalParameters.artifact.digest.sha256' "$predicate")" = "$digest" ] \
  || fail "provenance digest does not match the derived digest"
[ "$(jq -r '.buildDefinition.externalParameters.chart.version' "$predicate")" = "$version" ] \
  || fail "provenance chart version mismatch"
[ "$(jq -r '.buildDefinition.externalParameters.source.commit' "$predicate")" = "$(git rev-parse HEAD)" ] \
  || fail "provenance commit mismatch"

sbom="$NEW_STATE/work/ksvc-${version}.spdx.json"
[ -f "$sbom" ] || fail "SBOM was not written"
[ "$(jq -r '.spdxVersion' "$sbom")" = "SPDX-2.3" ] || fail "SBOM is not SPDX JSON"
echo "OK: signing, SBOM, attestation, and release upload are wired correctly"

# ---------------------------------------------------------------------------
# 2. Syft failure prevents any signing.
# ---------------------------------------------------------------------------
new_state syft-failure
FAKE_FAIL=syft run_sign
[ "$RC" -ne 0 ] || fail "Syft failure unexpectedly succeeded"
assert_not_contains "$NEW_STATE/tools.log" "cosign sign"
assert_contains "$NEW_STATE/run.log" "forced failure"
echo "OK: SBOM failure fails the release before signing"

# ---------------------------------------------------------------------------
# 3. Attestation failure fails the release after signing.
# ---------------------------------------------------------------------------
new_state attest-failure
FAKE_FAIL=attest run_sign
[ "$RC" -ne 0 ] || fail "attestation failure unexpectedly succeeded"
assert_contains "$NEW_STATE/tools.log" "cosign sign --yes"
assert_contains "$NEW_STATE/tools.log" "cosign attest"
assert_not_contains "$NEW_STATE/tools.log" "gh release upload"
echo "OK: attestation failure fails the release closed"
