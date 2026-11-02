#!/usr/bin/env bash
#
# test-find-previous-version.sh — exercise previous-release discovery against a
# fake registry API. No network access is used.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "test-find-previous-version: FAIL: $*" >&2
  exit 1
}

bin="$tmp/bin"
state="$tmp/state"
mkdir -p "$bin" "$state"

cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "curl $*" >> "$FAKE_STATE/curl.log"
case "$*" in
  *"/token"*)
    if [ -n "${FAKE_CURL_TOKEN_FAIL:-}" ]; then
      exit 22
    fi
    printf '%s\n' '{"token":"test-registry-token"}'
    ;;
  *"/tags/list"*)
    if [ -n "${FAKE_CURL_TAGS_FAIL:-}" ]; then
      exit 22
    fi
    cat "$FAKE_STATE/tags.json"
    ;;
  *)
    echo "fake curl: unexpected request: $*" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$bin/curl"

run_discovery() {
  local current="$1"
  set +e
  PATH="$bin:$PATH" FAKE_STATE="$state" \
    bash hack/release/find-previous-version.sh \
      --repository oci://ghcr.io/test-org/charts/ksvc \
      --current "$current" > "$state/stdout" 2> "$state/stderr"
  rc=$?
  set -e
}

tags_json() {
  local tags="$1"
  jq -cn --argjson tags "$tags" '{name: "test-org/charts/ksvc", tags: $tags}' > "$state/tags.json"
}

# --- Highest lower stable release wins -------------------------------------
tags_json '["sha256-abc.sig", "0.9.0", "1.0.0", "1.1.0", "2.0.0", "not-a-version"]'
run_discovery "1.1.0"
[ "$rc" -eq 0 ] || fail "stable discovery exited $rc: $(cat "$state/stderr")"
[ "$(cat "$state/stdout")" = "1.0.0" ] || fail "expected 1.0.0, got '$(cat "$state/stdout")'"
echo "OK: previews non-SemVer tags and selects the highest lower stable version"

# --- Prerelease ordering ----------------------------------------------------
tags_json '["1.0.0-rc.1", "1.0.0-rc.1.1", "1.0.0-rc.1.2", "1.0.0-rc.1.3", "0.10.0"]'
run_discovery "1.0.0-rc.1.3"
[ "$rc" -eq 0 ] || fail "prerelease discovery exited $rc: $(cat "$state/stderr")"
[ "$(cat "$state/stdout")" = "1.0.0-rc.1.2" ] || fail "expected 1.0.0-rc.1.2, got '$(cat "$state/stdout")'"
echo "OK: prerelease versions compare in SemVer order"

# --- A stable release is newer than its prereleases -------------------------
tags_json '["1.0.0-rc.1", "0.9.0"]'
run_discovery "1.0.0"
[ "$rc" -eq 0 ] || fail "stable/prerelease discovery exited $rc: $(cat "$state/stderr")"
[ "$(cat "$state/stdout")" = "1.0.0-rc.1" ] || fail "expected 1.0.0-rc.1, got '$(cat "$state/stdout")'"
echo "OK: the stable version sorts after its own prereleases"

# --- No lower version: successful no-op, with an explicit log ---------------
tags_json '["1.1.0", "2.0.0"]'
run_discovery "1.1.0"
[ "$rc" -eq 0 ] || fail "no-previous-version discovery exited $rc: $(cat "$state/stderr")"
[ -z "$(cat "$state/stdout")" ] || fail "expected no stdout for first-ever release"
grep -q "no published version lower than 1.1.0" "$state/stderr" \
  || fail "no-previous-version discovery did not log that discovery was attempted"
echo "OK: first-ever release returns empty only after attempting discovery"

# --- Non-SemVer current versions are rejected -------------------------------
tags_json '["1.0.0"]'
run_discovery "latest"
[ "$rc" -ne 0 ] || fail "non-SemVer current version was accepted"
grep -q "is not a SemVer version" "$state/stderr" || fail "missing invalid-current error"
echo "OK: invalid current versions fail loudly"

# --- Registry failures are not mistaken for a first-ever release ------------
tags_json '["1.0.0"]'
set +e
PATH="$bin:$PATH" FAKE_STATE="$state" FAKE_CURL_TAGS_FAIL=1 \
  bash hack/release/find-previous-version.sh \
    --repository ghcr.io/test-org/charts/ksvc \
    --current 2.0.0 > "$state/stdout" 2> "$state/stderr"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "registry tag-list failure was swallowed"
grep -q "Could not list published tags" "$state/stderr" || fail "missing registry failure message"
echo "OK: registry failures exit non-zero instead of skipping the upgrade"

# --- Token authentication is sent to the registry ---------------------------
: > "$state/curl.log"
tags_json '["1.0.0", "1.1.0"]'
set +e
PATH="$bin:$PATH" FAKE_STATE="$state" \
  REGISTRY_TOKEN="secret-token" REGISTRY_USERNAME="test-user" \
  bash hack/release/find-previous-version.sh \
    --repository ghcr.io/test-org/charts/ksvc \
    --current 1.1.0 > "$state/stdout" 2> "$state/stderr"
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "authenticated discovery exited $rc: $(cat "$state/stderr")"
grep -q -- "-u test-user:secret-token" "$state/curl.log" || fail "curl did not use the registry credential"
grep -q "Authorization: Bearer test-registry-token" "$state/curl.log" || fail "tags request did not use the registry token"
echo "OK: registry credentials produce an authenticated tag-list request"

# --- Malformed JSON is a failure, not an empty result -----------------------
printf '%s\n' 'not json' > "$state/tags.json"
run_discovery "1.0.0"
[ "$rc" -ne 0 ] || fail "malformed registry JSON was accepted"
grep -q "not valid JSON" "$state/stderr" || fail "missing malformed JSON error"
echo "OK: malformed registry responses fail loudly"

echo "All find-previous-version tests passed."
