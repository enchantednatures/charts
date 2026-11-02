#!/usr/bin/env bash
#
# check-action-pins.sh — reject mutable refs in GitHub Actions `uses:` lines.
#
# Every remote action must be pinned to a full 40-character commit SHA. Local
# actions (./path) are allowed, and docker:// references must use a
# sha256:<64 hex> digest. The check runs in CI and fails closed.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

shopt -s nullglob globstar
files=(
  .github/workflows/*.yaml
  .github/workflows/*.yml
  .github/actions/**/action.yaml
  .github/actions/**/action.yml
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "check-action-pins: no workflow or action files found" >&2
  exit 1
fi

failures=0
checked=0

while IFS= read -r entry; do
  file="${entry%%:*}"
  rest="${entry#*:}"
  lineno="${rest%%:*}"
  line="${rest#*:}"

  [[ "$line" =~ ^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*([^[:space:]#]+) ]] || continue
  ref="${BASH_REMATCH[2]}"
  checked=$((checked + 1))

  case "$ref" in
    ./*)
      continue
      ;;
    docker://*)
      if [[ ! "$ref" =~ @sha256:[0-9a-f]{64}$ ]]; then
        echo "::error file=${file},line=${lineno}::Docker action '$ref' must be pinned to a sha256 digest"
        failures=$((failures + 1))
      fi
      ;;
    *)
      if [[ ! "$ref" =~ @[0-9a-f]{40}$ ]]; then
        echo "::error file=${file},line=${lineno}::Action '$ref' must be pinned to a full 40-character commit SHA"
        failures=$((failures + 1))
      fi
      ;;
  esac
done < <(grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:' "${files[@]}" || true)

if [ "$failures" -ne 0 ]; then
  echo "check-action-pins: ${failures} unpinned action reference(s) found" >&2
  exit 1
fi

echo "check-action-pins: ${checked} action reference(s) pinned"
