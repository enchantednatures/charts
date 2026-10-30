#!/usr/bin/env bash
# Install only the Redpanda CRDs (no controller). The operator chart installs
# CRDs through a post-install job, so fetch the three stable CRDs upstream.
set -euo pipefail

operator_version="${REDPANDA_OPERATOR_VERSION:-26.2.5}"
base="https://raw.githubusercontent.com/redpanda-data/redpanda-operator/operator/v${operator_version}/operator/config/crd/bases"

for crd in \
  cluster.redpanda.com_redpandas.yaml \
  cluster.redpanda.com_topics.yaml \
  cluster.redpanda.com_users.yaml; do
  kubectl apply --server-side -f "${base}/${crd}"
done
