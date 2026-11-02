#!/usr/bin/env bash
#
# check-lock-consistency.sh — fail when a committed Chart.lock does not match
# its Chart.yaml or when `helm dependency build` rewrites it.
#
# Every chart that ships a lock file is resolved from that lock. `helm
# dependency build` refuses to proceed when the lock is out of sync with
# Chart.yaml, and a build that does rewrite a lock (for example because a
# resolver changed it) fails the `git status` check afterwards.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

charts=(charts/app/ksvc charts/library/ksvc/test-chart)
for example in examples/*/; do
  [ -f "$example/Chart.yaml" ] || continue
  charts+=("$example")
done

for chart in "${charts[@]}"; do
  echo "--- Verifying lock: $chart ---"
  python3 hack/check-chart-lock.py "$chart"
  helm dependency build "$chart"
done

changed="$(git status --porcelain -- ':(glob)**/Chart.lock')"
if [ -n "$changed" ]; then
  echo "::error::helm dependency build rewrote committed Chart.lock files; refresh them with 'make update-locks' and commit the result:"
  echo "$changed"
  exit 1
fi

echo "All committed Chart.lock files are consistent."
