#!/usr/bin/env bash
#
# detect-charts.sh — build the release matrix for push, tag, and dispatch
# events.
#
# push to main : charts whose Chart.yaml version changed in the pushed commit
# tag push     : the chart encoded in <chart>-v<version>
# dispatch     : explicit chart + version. The expected release commit is the
#                commit that introduced that version in the chart, or the
#                commit supplied in the dispatch input. There is no HEAD~1
#                fallback for dispatches.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

event_name="${EVENT_NAME:-${GITHUB_EVENT_NAME:-}}"
ref="${REF:-${GITHUB_REF:-}}"
input_chart="${INPUT_CHART:-}"
input_version="${INPUT_VERSION:-}"
input_commit="${INPUT_COMMIT:-}"
input_repair="${INPUT_REPAIR:-false}"

case "${input_repair,,}" in
  true|1|yes) repair=true ;;
  *) repair=false ;;
esac

charts='[]'
has_library=false
release_commit=''

chart_field() {
  local chart_yaml="$1" field="$2"
  grep "^${field}:" "$chart_yaml" | head -1 | awk '{print $2}'
}

find_chart_by_name() {
  local wanted="$1" candidate name
  for candidate in charts/library/*/Chart.yaml charts/app/*/Chart.yaml; do
    [ -f "$candidate" ] || continue
    name="$(chart_field "$candidate" name)"
    if [ "$name" = "$wanted" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

add_chart() {
  local name="$1" version="$2" path="$3" type="$4" tag="$5" commit="$6"
  charts="$(jq -c \
    --arg name "$name" \
    --arg version "$version" \
    --arg path "$path" \
    --arg type "$type" \
    --arg tag "$tag" \
    --arg commit "$commit" \
    --arg repair "$repair" \
    '. + [{"name": $name, "version": $version, "path": $path, "type": $type, "tag": $tag, "commit": $commit, "repair": $repair}]' \
    <<<"$charts")"
  if [ "$type" = "library" ]; then
    has_library=true
  fi
}

version_at_commit() {
  local commit="$1" chart_yaml="$2"
  git show "${commit}:${chart_yaml}" 2>/dev/null \
    | grep '^version:' | head -1 | awk '{print $2}' || true
}

derive_release_commit() {
  local chart_yaml="$1" wanted="$2" commit current parent
  while IFS= read -r commit; do
    [ -n "$commit" ] || continue
    current="$(version_at_commit "$commit" "$chart_yaml")"
    [ "$current" = "$wanted" ] || continue
    parent="$(version_at_commit "${commit}^" "$chart_yaml")"
    if [ "$parent" != "$wanted" ]; then
      printf '%s\n' "$commit"
      return 0
    fi
  done < <(git log --format=%H -- "$chart_yaml")
  return 1
}

if [ "$event_name" = "workflow_dispatch" ]; then
  if [[ -z "$input_chart" || -z "$input_version" ]]; then
    echo "::error::workflow_dispatch requires both 'chart' and 'version' inputs" >&2
    exit 1
  fi

  chart_yaml="$(find_chart_by_name "$input_chart")" || {
    echo "::error::No chart found with name '$input_chart'" >&2
    exit 1
  }

  chart_type="$(chart_field "$chart_yaml" type)"

  # Validate the requested version at the release commit, not at HEAD: a repair
  # dispatch may target an older release after main has moved on to a newer
  # chart version.
  if [ -n "$input_commit" ]; then
    if ! release_commit="$(git rev-parse --verify "${input_commit}^{commit}" 2>/dev/null)"; then
      echo "::error::Dispatch commit '$input_commit' does not exist in this checkout" >&2
      exit 1
    fi
    commit_version="$(version_at_commit "$release_commit" "$chart_yaml")"
    if [ "$commit_version" != "$input_version" ]; then
      echo "::error::Commit $release_commit has $chart_yaml version '$commit_version', not '$input_version'" >&2
      exit 1
    fi
  else
    if ! release_commit="$(derive_release_commit "$chart_yaml" "$input_version")"; then
      echo "::error::Could not derive the commit that introduced $input_chart version $input_version. Pass the 'commit' dispatch input explicitly." >&2
      exit 1
    fi
  fi

  add_chart \
    "$input_chart" "$input_version" "$(dirname "$chart_yaml")" \
    "$chart_type" "${input_chart}-v${input_version}" "$release_commit"

elif [[ "$ref" == refs/tags/* ]]; then
  tag="${ref#refs/tags/}"
  chart_name="${tag%-v*}"
  chart_version="${tag##*-v}"

  if [[ -z "$chart_name" || -z "$chart_version" ]]; then
    echo "::error::Tag '$tag' does not match pattern '<chart-name>-v<version>'" >&2
    exit 1
  fi

  chart_yaml="$(find_chart_by_name "$chart_name")" || {
    echo "::error::No chart found with name '$chart_name'" >&2
    exit 1
  }

  release_commit="$(git rev-parse HEAD^{commit})"
  add_chart \
    "$chart_name" "$chart_version" "$(dirname "$chart_yaml")" \
    "$(chart_field "$chart_yaml" type)" "$tag" "$release_commit"

else
  release_commit="$(git rev-parse HEAD^{commit})"

  for chart_yaml in $(git diff HEAD~1 --name-only -- 'charts/*/Chart.yaml' 'charts/*/*/Chart.yaml' | grep 'Chart\.yaml$' || true); do
    [ -f "$chart_yaml" ] || continue

    chart_name="$(chart_field "$chart_yaml" name)"
    new_version="$(chart_field "$chart_yaml" version)"
    [ -n "$chart_name" ] && [ -n "$new_version" ] || continue

    old_version="$(git show "HEAD~1:${chart_yaml}" 2>/dev/null | grep '^version:' | head -1 | awk '{print $2}' || true)"
    [ "$old_version" = "$new_version" ] && continue

    add_chart \
      "$chart_name" "$new_version" "$(dirname "$chart_yaml")" \
      "$(chart_field "$chart_yaml" type)" \
      "${chart_name}-v${new_version}" "$release_commit"
  done
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    printf 'matrix={"include":%s}\n' "$charts"
    printf 'has_library=%s\n' "$has_library"
    printf 'release_commit=%s\n' "$release_commit"
  } >> "$GITHUB_OUTPUT"
fi

echo "Release matrix: {\"include\":${charts}}"
echo "Release commit: ${release_commit}"
echo "Has library chart: ${has_library}"
