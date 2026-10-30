#!/usr/bin/env bash
# Install only the Redpanda CRDs (no controller). Helm is used to extract the
# chart's CRDs so the Makefile target remains CRD-only.
set -euo pipefail

operator_version="${REDPANDA_OPERATOR_VERSION:-26.2.5}"

helm repo add --force-update redpanda https://charts.redpanda.com >/dev/null
helm repo update redpanda >/dev/null
helm show crds redpanda/operator --version "$operator_version" | kubectl apply --server-side -f -
