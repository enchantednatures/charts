#!/usr/bin/env bash
#
# update-dependents.sh — bump dependent app charts and refresh every committed
# Chart.lock after a library chart release, then open one PR.
#
# The release matrix must describe the charts just published. Only library
# entries are considered. The checkout must be the release commit (the workflow
# checks out detect.outputs.release_commit), so tag-triggered releases bump from
# the tagged chart version rather than from whatever main contains later.
#
# Locks refreshed in the same PR:
#   charts/app/*/Chart.lock
#   charts/library/*/test-chart/Chart.lock
#   examples/*/Chart.lock
#
# The PR is pushed with GH_TOKEN. In CI, GH_TOKEN is RELEASE_BOT_TOKEN when that
# secret is configured, otherwise GITHUB_TOKEN; the fallback is documented
# because GitHub may not start pull_request workflows for GITHUB_TOKEN-authored
# PRs.
#
# Usage:
#   RELEASED_MATRIX='{"include":[...]}' GITHUB_REPOSITORY=owner/repo \
#     GH_TOKEN=... hack/release/update-dependents.sh \
#       --release-commit <sha> [--branch-name <name>] [--base-branch main]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
matrix_json="${RELEASED_MATRIX:-}"
release_commit=""
base_branch="main"
branch_name=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --matrix-json) matrix_json="${2:?--matrix-json requires a value}"; shift 2 ;;
    --release-commit) release_commit="${2:?--release-commit requires a value}"; shift 2 ;;
    --base-branch) base_branch="${2:?--base-branch requires a value}"; shift 2 ;;
    --branch-name) branch_name="${2:?--branch-name requires a value}"; shift 2 ;;
    --repo-root) repo_root="${2:?--repo-root requires a value}"; shift 2 ;;
    -h|--help)
      sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "update-dependents.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$matrix_json" ]; then
  echo "::error::update-dependents.sh: release matrix is empty" >&2
  exit 2
fi

for tool in git jq make helm python3 gh; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "::error::update-dependents.sh requires '$tool' on PATH" >&2
    exit 1
  fi
done

cd "$repo_root"

if ! jq -e '.include | type == "array"' <<<"$matrix_json" >/dev/null 2>&1; then
  echo "::error::update-dependents.sh: release matrix is not a JSON object with an include array" >&2
  exit 2
fi

if [ -n "$release_commit" ]; then
  resolved_release_commit="$(git rev-parse --verify "${release_commit}^{commit}" 2>/dev/null)" || {
    echo "::error::update-dependents.sh: release commit '$release_commit' does not exist in this checkout" >&2
    exit 1
  }
  head_commit="$(git rev-parse HEAD)"
  if [ "$resolved_release_commit" != "$head_commit" ]; then
    echo "::error::update-dependents.sh: checkout is $head_commit but the release commit is $resolved_release_commit. Check out the tagged release commit before bumping dependents." >&2
    exit 1
  fi
  echo "Using release commit $resolved_release_commit"
fi

library_names=()
library_versions=()
while IFS=$'\t' read -r name version; do
  [ -n "$name" ] || continue
  library_names+=("$name")
  library_versions+=("$version")
done < <(jq -r '.include[] | select(.type == "library") | [.name, .version] | @tsv' <<<"$matrix_json")

if [ "${#library_names[@]}" -eq 0 ]; then
  echo "::notice::No library charts in the release matrix; dependent bumps are not needed."
  exit 0
fi

chart_depends_on() {
  local chart_yaml="$1" dependency="$2"
  awk -v dependency="$dependency" '
    /^dependencies:[[:space:]]*$/ { in_deps = 1; next }
    in_deps && /^[^[:space:]-]/ { in_deps = 0 }
    in_deps && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
      name = $0
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", name)
      gsub(/["\047]/, "", name)
      if (name == dependency) { found = 1 }
    }
    END { exit found ? 0 : 1 }
  ' "$chart_yaml"
}

lock_pins_version() {
  local lock_file="$1" dependency="$2" version="$3"
  awk -v dependency="$dependency" -v wanted="$version" '
    /^- name:[[:space:]]*/ {
      name = $0
      sub(/^- name:[[:space:]]*/, "", name)
      gsub(/["\047]/, "", name)
      in_dependency = (name == dependency)
      next
    }
    in_dependency && /^[[:space:]]+version:[[:space:]]*/ {
      version = $0
      sub(/^[[:space:]]+version:[[:space:]]*/, "", version)
      gsub(/["\047]/, "", version)
      if (version != wanted) {
        printf "dependency %s is pinned to %s, expected %s\n", dependency, version, wanted > "/dev/stderr"
        exit 1
      }
      found = 1
      exit
    }
    END {
      if (!found) {
        printf "dependency %s is missing from the lock\n", dependency > "/dev/stderr"
        exit 1
      }
    }
  ' "$lock_file"
}

if [ -n "$(git status --porcelain)" ]; then
  echo "::error::update-dependents.sh: working tree must be clean before bumping dependents" >&2
  exit 1
fi

original_ref="$(git symbolic-ref --quiet --short HEAD || true)"
original_commit="$(git rev-parse HEAD)"
branch_name="${branch_name:-chore/bump-deps-$(date +%s)-${GITHUB_RUN_ID:-local}}"

git checkout -b "$branch_name"

pr_body="$(mktemp)"
markdown_tick='`'
trap 'rm -f "$pr_body"' EXIT

{
  echo "Automated dependency bump triggered by a library chart release."
  echo
  echo "Released library charts:"
  for index in "${!library_names[@]}"; do
    echo "- \`${library_names[$index]}\` -> \`${library_versions[$index]}\`"
  done
  echo
  echo "Updated application charts:"
} > "$pr_body"

updated_any=false
for app_chart in charts/app/*/Chart.yaml; do
  [ -f "$app_chart" ] || continue

  dependencies=()
  for index in "${!library_names[@]}"; do
    if chart_depends_on "$app_chart" "${library_names[$index]}"; then
      dependencies+=("${library_names[$index]}=${library_versions[$index]}")
    fi
  done
  if [ "${#dependencies[@]}" -eq 0 ]; then
    continue
  fi

  app_name="$(grep '^name:' "$app_chart" | head -1 | awk '{print $2}')"
  old_app_version="$(grep '^version:' "$app_chart" | head -1 | awk '{print $2}')"

  python3 "$script_dir/update-dependent-chart.py" "$app_chart" \
    --bump patch --dependency "${dependencies[@]}"

  new_app_version="$(grep '^version:' "$app_chart" | head -1 | awk '{print $2}')"
  printf -- '- %s%s%s %s -> %s' \
    "$markdown_tick" "$app_name" "$markdown_tick" "$old_app_version" "$new_app_version" >> "$pr_body"
  for dependency in "${dependencies[@]}"; do
    printf ' (%s)' "$dependency" >> "$pr_body"
  done
  printf '\n' >> "$pr_body"
  updated_any=true
done

if [ "$updated_any" = false ]; then
  echo "No application chart depends on the released library; refreshing locks only."
  echo "No application chart depends on the released library." >> "$pr_body"
fi

echo "Refreshing all committed Chart.lock files"
if ! make update-locks; then
  echo "::error::update-dependents.sh: 'make update-locks' failed; cannot open a dependent bump PR with stale locks" >&2
  exit 1
fi

lock_files=()
for candidate in charts/app/*/Chart.lock charts/library/*/test-chart/Chart.lock examples/*/Chart.lock; do
  [ -f "$candidate" ] && lock_files+=("$candidate")
done
if [ "${#lock_files[@]}" -eq 0 ]; then
  echo "::error::update-dependents.sh: no Chart.lock files found after 'make update-locks'" >&2
  exit 1
fi

# Stage first so a `helm dependency build` that rewrites a lock after refresh is
# visible as an unstaged diff rather than being mistaken for the intended change.
git add -- charts/app/*/Chart.yaml "${lock_files[@]}"

# Verify the refreshed locks are structurally consistent and that a real
# `helm dependency build` accepts them without rewriting the committed files.
for chart_dir in charts/app/* charts/library/*/test-chart examples/*; do
  [ -f "$chart_dir/Chart.yaml" ] || continue
  python3 hack/check-chart-lock.py "$chart_dir"
  if [ -f "$chart_dir/Chart.lock" ]; then
    helm dependency build "$chart_dir" >/dev/null
  fi
done

if ! git diff --quiet -- ':(glob)**/Chart.lock'; then
  echo "::error::update-dependents.sh: 'helm dependency build' rewrote a staged lock. Run 'make update-locks' and commit the result." >&2
  exit 1
fi

for lock_file in "${lock_files[@]}"; do
  for index in "${!library_names[@]}"; do
    if grep -q "name: ${library_names[$index]}" "$lock_file"; then
      lock_pins_version "$lock_file" "${library_names[$index]}" "${library_versions[$index]}" || {
        echo "::error::${lock_file} does not pin ${library_names[$index]} ${library_versions[$index]}" >&2
        exit 1
      }
    fi
  done
  printf -- '- %s%s%s\n' "$markdown_tick" "$lock_file" "$markdown_tick" >> "$pr_body"
done

if git diff --cached --quiet; then
  echo "::notice::Dependents and locks already match the release; nothing to commit."
  git checkout -- .
  if [ -n "$original_ref" ]; then
    git checkout --quiet "$original_ref"
  else
    git checkout --quiet --detach "$original_commit"
  fi
  git branch -D "$branch_name" >/dev/null
  exit 0
fi

if ! git config user.email >/dev/null 2>&1; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
fi

git commit -m "chore: bump dependent charts for ${library_names[*]}"
if ! git push origin "$branch_name"; then
  echo "::error::update-dependents.sh: could not push branch '$branch_name'. Check the token permissions (contents: write)." >&2
  exit 1
fi

if [ -z "${RELEASE_BOT_TOKEN:-}" ]; then
  echo "::notice::RELEASE_BOT_TOKEN is not set; using GITHUB_TOKEN. The PR will be created, but pull_request workflows may not run for a GITHUB_TOKEN-authored PR. Configure the RELEASE_BOT_TOKEN secret (GitHub App or PAT with contents: write and pull-requests: write) to make the bump PR run CI."
fi

if ! pr_url="$(gh pr create \
  --repo "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}" \
  --title "chore: bump dependent charts for ${library_names[*]}" \
  --body-file "$pr_body" \
  --base "$base_branch" \
  --head "$branch_name")"; then
  echo "::error::update-dependents.sh: dependent bump branch '$branch_name' was pushed, but opening the PR failed. Check GH_TOKEN/RELEASE_BOT_TOKEN pull-requests: write permission." >&2
  exit 1
fi

echo "Opened dependent bump PR: ${pr_url}"
