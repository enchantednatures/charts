#!/usr/bin/env bash
# Install the Strimzi operator and CRDs for a Kind e2e. The chart never
# installs cluster-scoped controllers; this script is a local/CI prerequisite.
set -euo pipefail

strimzi_version="${STRIMZI_VERSION:-1.3.0}"
namespace="${STRIMZI_NAMESPACE:-strimzi-system}"
release="${STRIMZI_RELEASE:-strimzi-cluster-operator}"

kubectl apply --server-side -f \
  "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${strimzi_version}/strimzi-crds-${strimzi_version}.yaml"

helm repo add --force-update strimzi https://strimzi.io/charts/ >/dev/null
helm repo update strimzi >/dev/null
helm upgrade --install "$release" strimzi/strimzi-kafka-operator \
  --version "$strimzi_version" \
  --namespace "$namespace" \
  --create-namespace \
  --set watchAnyNamespace=true \
  --wait \
  --timeout 10m

kubectl -n "$namespace" rollout status deployment -l "app.kubernetes.io/instance=${release}" --timeout=300s
