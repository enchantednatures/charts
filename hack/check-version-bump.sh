#!/usr/bin/env bash
#
# check-version-bump.sh — PR-time gate: a chart whose packaging-relevant source
# changes must have its Chart.yaml `version:` strictly increased against the PR
# base ref, so a merge can never silently release nothing.
#
# The release workflow (release.yaml) only starts when a `charts/**/Chart.yaml`
# version changes on main. Without this gate a PR can edit templates without
# bumping `version:`, merge, and publish nothing — undetected. This script makes
# that a hard PR failure.
#
# Rules
# -----
# The diff is computed as `<base-ref>...HEAD` (three-dot / merge-base), so a
# stacked PR is judged only on its own changes, not on the commits it is stacked
# on top of.
#
# For every library chart under charts/library/*/:
#   if any changed file under the chart (EXCLUDING README.md, Chart.lock and
#   test-chart/**) exists, Chart.yaml `version:` must strictly increase. A
#   Chart.yaml-only edit still counts (the file is not excluded).
#
# For every app chart under charts/app/*/:
#   if any changed file under the chart (EXCLUDING README.md, Chart.lock and
#   Chart.yaml) exists, `version:` must strictly increase. App Chart.yaml is
#   excluded because feature PRs only bump the ksvc dependency version there;
#   app releases are bot-managed.
#
# "Strictly increase" means new > old (equal or lower is a failure). Charts that
# appear only on the HEAD side (new charts) have no prior version to increase
# from, so only version presence is required; charts only on the base side are
# deletions and need no bump.
#
# Usage:
#   hack/check-version-bump.sh <base-ref>
#
# Examples:
#   hack/check-version-bump.sh origin/main
#   hack/check-version-bump.sh origin/fix/ci-dep-build-locks
#
# Exit codes:
#   0  no requirement violated (or nothing to check)
#   1  a chart changed without a version bump, or the base ref is unknown
#   2  usage error
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
  cat >&2 <<'EOF'
Usage: hack/check-version-bump.sh <base-ref>

  <base-ref>  Git ref to diff against (e.g. origin/main, origin/<branch>).
              The diff is <base-ref>...HEAD (merge-base) so stacked PRs only
              count their own changes.
EOF
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

base_ref="$1"

if ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null; then
  echo "::error::check-version-bump: base ref '${base_ref}' not found." >&2
  echo "Fetch it first (e.g. git fetch origin) or pass a valid ref." >&2
  exit 1
fi

changed_files="$(git diff --name-only "${base_ref}...HEAD")"

# Version of a chart's Chart.yaml as of the base ref (empty if absent).
base_version() {
  git show "${base_ref}:$1" 2>/dev/null | grep '^version:' | head -1 | awk '{print $2}' || true
}

# Version of a chart's Chart.yaml in the current working tree.
worktree_version() {
  grep '^version:' "$1" | head -1 | awk '{print $2}' || true
}

# Relevant (non-excluded) changed files for a chart directory.
relevant_changes() {
  local chart_dir="$1" kind="$2" f rel
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      "$chart_dir"/*) ;;
      *) continue ;;
    esac
    rel="${f#"$chart_dir"/}"
    case "$kind" in
      library)
        case "$rel" in
          README.md|Chart.lock) continue ;;
          test-chart/*) continue ;;
        esac
        ;;
      app)
        case "$rel" in
          README.md|Chart.lock|Chart.yaml) continue ;;
        esac
        ;;
    esac
    echo "$f"
  done <<< "$changed_files"
}

# True (0) when "$2" is strictly greater than "$1" under version sort.
strictly_greater() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}

violations=0

check_chart() {
  local chart_dir="$1" kind="$2" chart_yaml new_version old_version

  [ -n "$(relevant_changes "$chart_dir" "$kind")" ] || return 0

  chart_yaml="$chart_dir/Chart.yaml"
  new_version="$(worktree_version "$chart_yaml")"
  old_version="$(base_version "$chart_yaml")"

  if [ -z "$new_version" ]; then
    echo "::error::${chart_yaml}: chart files changed but no 'version:' field is present."
    return 1
  fi

  if [ -z "$old_version" ]; then
    echo "OK: ${chart_dir} is new (version ${new_version}); no prior version to bump."
    return 0
  fi

  if strictly_greater "$old_version" "$new_version"; then
    echo "OK: ${chart_dir} version bumped ${old_version} -> ${new_version}."
    return 0
  fi

  echo "::error::${chart_yaml}: chart files changed but 'version:' was not increased (base ${old_version}, current ${new_version}). Bump the 'version:' field in ${chart_yaml}."
  return 1
}

for chart_dir in charts/library/*/; do
  [ -d "$chart_dir" ] || continue
  check_chart "${chart_dir%/}" library || violations=$((violations + 1))
done

for chart_dir in charts/app/*/; do
  [ -d "$chart_dir" ] || continue
  check_chart "${chart_dir%/}" app || violations=$((violations + 1))
done

if [ "$violations" -gt 0 ]; then
  echo "::error::check-version-bump: ${violations} chart(s) changed without a version bump."
  exit 1
fi

echo "check-version-bump: OK (no version bump required)."
