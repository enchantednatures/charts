#!/usr/bin/env bash
#
# check-required-checks.sh — fail closed unless every required check on a
# release commit has completed successfully.
#
# Required names are matched exactly or by the matrix suffix convention
# "<name> (<matrix values>)". All matching check runs must pass, so every
# expanded matrix lane is gated. When GitHub returns multiple runs for the same
# name (re-runs), the newest run id wins.
#
# Usage:
#   hack/release/check-required-checks.sh --commit <sha> [--timeout 3300]
#                                         [--interval 20]
#                                         [--check-runs-json <fixture>]
set -euo pipefail

commit="${GITHUB_SHA:-}"
timeout_seconds=3300
interval_seconds=20
check_runs_json=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --commit)
      commit="${2:?--commit requires a value}"
      shift 2
      ;;
    --timeout)
      timeout_seconds="${2:?--timeout requires a value}"
      shift 2
      ;;
    --interval)
      interval_seconds="${2:?--interval requires a value}"
      shift 2
      ;;
    --check-runs-json)
      check_runs_json="${2:?--check-runs-json requires a value}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "check-required-checks.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$commit" ]; then
  echo "::error::No release commit supplied (use --commit or GITHUB_SHA)" >&2
  exit 2
fi

required=(
  "Helm Lint"
  "Schema Validation"
  "Template Rendering"
  "Helm Unit Tests"
  "Kubernetes Schema Validation"
  "Kind Cluster Deploy"
  "App Chart Dry-Run"
  "Kyverno Guardrails E2E"
  "Kafka Strimzi E2E"
)

required_json="$(jq -cn --args '$ARGS.positional' "${required[@]}")"

fetch_check_runs() {
  if [ -n "$check_runs_json" ]; then
    jq -c '.check_runs' "$check_runs_json"
    return
  fi

  if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo "::error::GITHUB_REPOSITORY is not set" >&2
    return 1
  fi

  gh api --paginate --slurp \
    "repos/${GITHUB_REPOSITORY}/commits/${commit}/check-runs?filter=latest&per_page=100" \
    | jq -c '[.[] | .check_runs[]]'
}

evaluate() {
  local runs="$1"
  jq -r --argjson required "$required_json" '
    . as $runs
    | $required[]
    | . as $prefix
    | ([ $runs[]
         | select(.name == $prefix or (.name | startswith($prefix + " (")))
       ]
       | group_by(.name)
       | map(max_by(.id))) as $latest
    | if ($latest | length) == 0 then
        ["MISSING", $prefix, "no check run found"] | @tsv
      else
        $latest[]
        | if .status != "completed" then
            ["PENDING", $prefix, (.name + "=" + (.status // "unknown"))] | @tsv
          elif .conclusion != "success" then
            ["FAILED", $prefix, (.name + "=" + (.conclusion // "none"))] | @tsv
          else empty
          end
      end
  ' <<<"$runs"
}

print_issues() {
  local issues="$1"
  while IFS=$'\t' read -r state prefix detail; do
    [ -n "$state" ] || continue
    echo "::error::Required check '${prefix}' is ${state}: ${detail}" >&2
  done <<<"$issues"
}

report_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  {
    echo "## Release gate: ${commit}"
    echo
    echo "All required checks completed successfully:"
    echo
    for name in "${required[@]}"; do
      echo "- ${name}"
    done
  } >> "$GITHUB_STEP_SUMMARY"
}

if [ -n "$check_runs_json" ]; then
  runs="$(fetch_check_runs)"
  issues="$(evaluate "$runs")"
  if [ -n "$issues" ]; then
    print_issues "$issues"
    exit 1
  fi
  echo "All required checks passed for ${commit} (fixture: ${check_runs_json})."
  exit 0
fi

deadline=$((SECONDS + timeout_seconds))

while :; do
  runs="$(fetch_check_runs)" || exit 1
  issues="$(evaluate "$runs")"

  if [ -n "$issues" ]; then
    if grep -q $'^FAILED\t' <<<"$issues"; then
      print_issues "$issues"
      echo "::error::One or more required checks failed; refusing to release ${commit}." >&2
      exit 1
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
      print_issues "$issues"
      echo "::error::Timed out after ${timeout_seconds}s waiting for required checks on ${commit}." >&2
      exit 1
    fi

    echo "Waiting for required checks on ${commit} (${SECONDS}s/${timeout_seconds}s):"
    while IFS=$'\t' read -r state prefix detail; do
      [ -n "$state" ] || continue
      echo "  - ${state}: ${prefix} (${detail})"
    done <<<"$issues"
    sleep "$interval_seconds"
    continue
  fi

  echo "All required checks completed successfully for ${commit}."
  report_summary
  exit 0
done
