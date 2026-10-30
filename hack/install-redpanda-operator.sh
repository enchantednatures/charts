#!/usr/bin/env bash
# Install the Redpanda operator and CRDs for a Kind e2e. The chart never
# installs cluster-scoped controllers; this script is a local/CI prerequisite.
set -euo pipefail

operator_version="${REDPANDA_OPERATOR_VERSION:-26.2.5}"
namespace="${REDPANDA_NAMESPACE:-redpanda-system}"
release="${REDPANDA_RELEASE:-redpanda-controller}"

helm repo add --force-update redpanda https://charts.redpanda.com >/dev/null
helm repo update redpanda >/dev/null
helm upgrade --install "$release" redpanda/operator \
  --version "$operator_version" \
  --namespace "$namespace" \
  --create-namespace \
  --set crds.enabled=true \
  --wait \
  --timeout 10m

kubectl -n "$namespace" rollout status "deployment/${release}-operator" --timeout=300s
