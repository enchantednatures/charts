#!/usr/bin/env bash
# Install Knative Eventing core for the Strimzi e2e. The chart never installs
# cluster-scoped controllers; this script is a local/CI prerequisite.
set -euo pipefail

version="${KNATIVE_VERSION:-v1.17.0}"
kubectl apply --server-side -f \
  "https://github.com/knative/eventing/releases/download/knative-${version}/eventing-core.yaml"
kubectl wait -n knative-eventing deployment/eventing-webhook \
  --for=condition=Available --timeout=300s
