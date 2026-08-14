# =============================================================================
# ksvc Helm Chart — Development & CRD Management
# =============================================================================
#
# Usage:
#   make install-all-crds          Install every CRD needed by the chart
#   make install-knative           Knative Serving CRDs only
#   make install-cnpg              CloudNativePG CRDs only
#   make install-kafka             Kafka (KafkaSource) CRDs only
#   make install-eventing          Knative Eventing (Broker/Trigger) CRDs only
#   make install-flagger           Flagger CRDs only
#   make install-dragonfly         DragonflyDB CRDs only
#   make install-monitoring        Prometheus Operator CRDs only
#   make create-kind-cluster       Create a Kind cluster + install all CRDs
#   make install-flux-sync         Apply Flux GitRepository + Kustomization
#   make install-local EXAMPLE=x   Install an example release into Kind
#   make template EXAMPLE=x        Render templates for an example
#   make lint                      Lint all charts and examples
#   make test                      Run helm-unittest
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Versions — single source of truth for CRD versions
# ---------------------------------------------------------------------------
KNATIVE_VERSION       ?= v1.17.0
CNPG_RELEASE          ?= release-1.25
FLAGGER_BRANCH        ?= main
KAFKA_EVENTING_VERSION ?= v1.17.0
DRAGONFLY_BRANCH      ?= main
HELM_VERSION          ?= v3.17.0
KIND_CLUSTER_NAME     ?= test-cluster
EXAMPLE               ?= minimal
NAMESPACE             ?= test-ns
FLUX_NAMESPACE        ?= flux-system

# ---------------------------------------------------------------------------
# CRD URLs
# ---------------------------------------------------------------------------
KNATIVE_SERVING_CRDS := https://github.com/knative/serving/releases/download/knative-$(KNATIVE_VERSION)/serving-crds.yaml

CNPG_CRD_BASE := https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/$(CNPG_RELEASE)/config/crd/bases
CNPG_CRDS := \
	$(CNPG_CRD_BASE)/postgresql.cnpg.io_clusters.yaml \
	$(CNPG_CRD_BASE)/postgresql.cnpg.io_poolers.yaml \
	$(CNPG_CRD_BASE)/postgresql.cnpg.io_scheduledbackups.yaml \
	https://raw.githubusercontent.com/cloudnative-pg/plugin-barman-cloud/main/config/crd/bases/barmancloud.cnpg.io_objectstores.yaml

PROMETHEUS_CRD_BASE := https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd
MONITORING_CRDS := \
	$(PROMETHEUS_CRD_BASE)/monitoring.coreos.com_podmonitors.yaml \
	$(PROMETHEUS_CRD_BASE)/monitoring.coreos.com_prometheusrules.yaml

FLAGGER_CRDS := https://raw.githubusercontent.com/fluxcd/flagger/$(FLAGGER_BRANCH)/artifacts/flagger/crd.yaml

KAFKA_SOURCE_CRDS := https://raw.githubusercontent.com/knative-extensions/eventing-kafka-broker/knative-$(KAFKA_EVENTING_VERSION)/control-plane/config/eventing-kafka-broker/100-source/100-kafka-source.yaml

EVENTING_CRDS := https://github.com/knative/eventing/releases/download/knative-$(KNATIVE_VERSION)/eventing-crds.yaml

DRAGONFLY_CRDS := https://raw.githubusercontent.com/dragonflydb/dragonfly-operator/$(DRAGONFLY_BRANCH)/config/crd/bases/dragonflydb.io_dragonflies.yaml

# ---------------------------------------------------------------------------
# Helper: kubectl apply with retries
# ---------------------------------------------------------------------------
define apply-with-retry
	@for url in $(1); do \
		echo "Installing CRD: $$url"; \
		for i in 1 2 3; do \
			kubectl apply --server-side -f "$$url" && break; \
			echo "  Attempt $$i failed, retrying in 5s..." && sleep 5; \
		done; \
	done
endef

# ---------------------------------------------------------------------------
# CRD install targets
# ---------------------------------------------------------------------------
.PHONY: install-knative
install-knative: ## Install Knative Serving CRDs
	$(call apply-with-retry,$(KNATIVE_SERVING_CRDS))
	kubectl wait --for=condition=Established crd/services.serving.knative.dev --timeout=60s

.PHONY: install-cnpg
install-cnpg: ## Install CloudNativePG CRDs
	$(call apply-with-retry,$(CNPG_CRDS))

.PHONY: install-monitoring
install-monitoring: ## Install Prometheus Operator CRDs (PodMonitor, PrometheusRule)
	$(call apply-with-retry,$(MONITORING_CRDS))

.PHONY: install-flagger
install-flagger: ## Install Flagger CRDs
	$(call apply-with-retry,$(FLAGGER_CRDS))

.PHONY: install-kafka
install-kafka: ## Install Kafka (KafkaSource) CRDs
	$(call apply-with-retry,$(KAFKA_SOURCE_CRDS))

.PHONY: install-eventing
install-eventing: ## Install Knative Eventing CRDs (Broker, Trigger)
	$(call apply-with-retry,$(EVENTING_CRDS))
	kubectl wait --for=condition=Established crd/brokers.eventing.knative.dev --timeout=60s
	kubectl wait --for=condition=Established crd/triggers.eventing.knative.dev --timeout=60s

.PHONY: install-dragonfly
install-dragonfly: ## Install DragonflyDB CRDs
	$(call apply-with-retry,$(DRAGONFLY_CRDS))

.PHONY: install-all-crds
install-all-crds: install-knative install-cnpg install-monitoring install-flagger install-kafka install-eventing install-dragonfly ## Install all CRDs

# ---------------------------------------------------------------------------
# Kind cluster management
# ---------------------------------------------------------------------------
.PHONY: create-kind-cluster
create-kind-cluster: ## Create a Kind cluster and install all CRDs
	@if kind get clusters 2>/dev/null | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
		echo "Kind cluster '$(KIND_CLUSTER_NAME)' already exists"; \
	else \
		kind create cluster --name $(KIND_CLUSTER_NAME) --wait 60s; \
	fi
	$(MAKE) install-all-crds

.PHONY: delete-kind-cluster
delete-kind-cluster: ## Delete the Kind cluster
	kind delete cluster --name $(KIND_CLUSTER_NAME)

# ---------------------------------------------------------------------------
# Flux GitOps sync
# ---------------------------------------------------------------------------
.PHONY: install-flux-sync
install-flux-sync: ## Apply Flux GitRepository + Kustomization from flux/
	kubectl apply -k flux/

.PHONY: uninstall-flux-sync
uninstall-flux-sync: ## Remove Flux sync resources
	kubectl delete -k flux/ --ignore-not-found

.PHONY: flux-reconcile
flux-reconcile: ## Trigger immediate Flux reconciliation
	flux reconcile source git charts -n $(FLUX_NAMESPACE)
	flux reconcile kustomization charts -n $(FLUX_NAMESPACE)

# ---------------------------------------------------------------------------
# Local development
# ---------------------------------------------------------------------------
.PHONY: install-local
install-local: ## Install an example into the local cluster (EXAMPLE=minimal)
	helm dependency update examples/$(EXAMPLE)
	helm upgrade --install test-$(EXAMPLE) examples/$(EXAMPLE) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--timeout 120s

.PHONY: uninstall-local
uninstall-local: ## Uninstall the local example release
	helm uninstall test-$(EXAMPLE) --namespace $(NAMESPACE) || true

.PHONY: template
template: ## Render templates for an example (EXAMPLE=minimal)
	helm dependency update examples/$(EXAMPLE)
	helm template test-$(EXAMPLE) examples/$(EXAMPLE) --namespace $(NAMESPACE)

# ---------------------------------------------------------------------------
# Lint & Test
# ---------------------------------------------------------------------------
.PHONY: lint
lint: ## Lint all charts and examples
	helm lint charts/library/ksvc
	@# App chart needs local dependency resolution
	@sed -i 's|repository: oci://ghcr.io/enchantednatures/charts|repository: "file://../../library/ksvc"|' charts/app/ksvc/Chart.yaml
	@helm dependency update charts/app/ksvc
	@helm lint charts/app/ksvc
	@git checkout charts/app/ksvc/Chart.yaml
	@for example in examples/*/; do \
		echo "--- Linting $$example ---"; \
		helm dependency update "$$example"; \
		helm lint "$$example"; \
	done

.PHONY: test
test: ## Run helm unit tests
	helm dependency build charts/library/ksvc/test-chart
	helm unittest charts/library/ksvc/test-chart

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
