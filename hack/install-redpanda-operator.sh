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

for _ in $(seq 1 60); do
  if kubectl get crd     redpandas.cluster.redpanda.com     topics.cluster.redpanda.com     users.cluster.redpanda.com >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

kubectl wait --for=condition=Established   crd/redpandas.cluster.redpanda.com   crd/topics.cluster.redpanda.com   crd/users.cluster.redpanda.com   --timeout=300s
