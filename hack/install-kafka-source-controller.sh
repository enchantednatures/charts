#!/usr/bin/env bash
# Install the Knative KafkaSource controller and conversion webhook for the
# Strimzi e2e. The chart never installs cluster-scoped controllers; this script
# is a local/CI prerequisite for tests that create a KafkaSource.
set -euo pipefail

version="${KAFKA_EVENTING_VERSION:-v1.17.0}"
namespace="knative-eventing"
bundle="https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${version}/eventing-kafka-source-bundle.yaml"

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -f "$bundle"
kubectl wait -n "$namespace" deployment/kafka-webhook-eventing \
  --for=condition=Available --timeout=300s

# The webhook self-bootstraps its serving certs and writes the CA into the
# KafkaSource CRD's conversion webhook. Wait for that before creating sources.
ca_bundle=""
for _ in $(seq 1 60); do
  ca_bundle="$(kubectl get crd kafkasources.sources.knative.dev \
    -o jsonpath='{.spec.conversion.webhook.clientConfig.caBundle}' 2>/dev/null || true)"
  if [ -n "$ca_bundle" ]; then
    break
  fi
  sleep 2
done
if [ -z "$ca_bundle" ]; then
  echo "kafka source CRD conversion webhook CA bundle was not populated" >&2
  exit 1
fi
