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
#   make install-object-bucket     ObjectBucketClaim + ObjectBucket CRDs only
#   make install-monitoring        Prometheus Operator CRDs only
#   make install-kyverno           Kyverno (CRDs + controllers) via Helm
#   make create-kind-cluster       Create a Kind cluster + install all CRDs
#   make install-flux-sync         Apply Flux GitRepository + Kustomization
#   make install-local EXAMPLE=x   Install an example release into Kind
#   make template EXAMPLE=x        Render templates for an example
#   make lint                      Lint all charts and examples
#   make test                      Run helm-unittest
#   make docs                      Regenerate the chart README with helm-docs
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
KYVERNO_CHART_VERSION ?= 3.9.1
HELM_VERSION          ?= v3.17.0
HELM_DOCS_VERSION     ?= v1.14.2
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

OBJECT_BUCKET_CRD_BASE := https://raw.githubusercontent.com/kube-object-storage/lib-bucket-provisioner/master/deploy/crds
OBJECT_BUCKET_CRDS := \
	$(OBJECT_BUCKET_CRD_BASE)/objectbucket_v1alpha1_objectbucketclaim_crd.yaml \
	$(OBJECT_BUCKET_CRD_BASE)/objectbucket_v1alpha1_objectbucket_crd.yaml

# ---------------------------------------------------------------------------
# Helper: kubectl apply with retries
# ---------------------------------------------------------------------------
define apply-with-retry
	@for url in $(1); do \
		echo "Installing CRD: $$url"; \
		success=0; \
		for i in 1 2 3; do \
			if kubectl apply --server-side -f "$$url"; then success=1; break; fi; \
			echo "  Attempt $$i failed, retrying in 5s..."; \
			sleep 5; \
		done; \
		if [ "$$success" -ne 1 ]; then \
			echo "ERROR: failed to apply $$url after 3 attempts"; \
			exit 1; \
		fi; \
	done
endef

# ---------------------------------------------------------------------------
# Helper: wait for CRDs to become Established, with retries
#
# A freshly applied CRD may not yet have .status.conditions populated when
# kubectl reads it, which makes `kubectl wait` abort with an "accessor error"
# instead of retrying. Retry the wait so the transient race does not fail CI,
# and only report failure (non-zero) after the final attempt.
# ---------------------------------------------------------------------------
define wait-established
	@for crd in $(1); do \
		echo "Waiting for CRD to be Established: $$crd"; \
		success=0; \
		for i in 1 2 3 4 5; do \
			if kubectl wait --for=condition=Established "crd/$$crd" --timeout=30s; then success=1; break; fi; \
			echo "  Attempt $$i failed, retrying in 5s..."; \
			sleep 5; \
		done; \
		if [ "$$success" -ne 1 ]; then \
			echo "ERROR: crd/$$crd did not become Established after 5 attempts"; \
			exit 1; \
		fi; \
	done
endef

# ---------------------------------------------------------------------------
# Helper: wait for the Kyverno policy admission webhook to actually serve
#
# `helm upgrade --install --wait` returns once the Kyverno Deployments report
# ready, but the validate-policy admission webhook can still refuse connections
# for a short window afterwards (Service endpoints / TLS bootstrap lag). Any
# Kyverno policy created in that window is rejected with "connection refused".
# Poll a real policy creation through the API server until it is admitted:
# server-side dry-run runs the full admission chain, including the
# validate-policy webhook, so connection-refused keeps looping instead of
# passing. Fail loudly if the webhook never serves (~3 min budget).
# ---------------------------------------------------------------------------
define wait-kyverno-webhook
	@echo "Waiting for the Kyverno validate-policy admission webhook to serve requests..."; \
	probe='apiVersion: policies.kyverno.io/v1beta1\nkind: NamespacedValidatingPolicy\nmetadata:\n  name: ksvc-webhook-readiness-probe\n  namespace: default\nspec:\n  validationActions:\n    - Deny\n  matchConstraints:\n    resourceRules:\n      - apiGroups: [""]\n        apiVersions: ["v1"]\n        resources: ["configmaps"]\n        operations: ["CREATE", "UPDATE"]\n  validations:\n    - expression: "true"\n      message: "readiness probe"\n'; \
	success=0; \
	for i in $$(seq 1 36); do \
		if printf "$$probe" | kubectl create --dry-run=server -f - >/dev/null 2>&1; then success=1; break; fi; \
		echo "  Attempt $$i/36: webhook not serving yet, retrying in 5s..."; \
		sleep 5; \
	done; \
	if [ "$$success" -ne 1 ]; then \
		echo "ERROR: Kyverno validate-policy admission webhook did not serve within 180s. Last probe output:"; \
		printf "$$probe" | kubectl create --dry-run=server -f - || true; \
		exit 1; \
	fi; \
	echo "Kyverno validate-policy admission webhook is serving requests."
endef

# ---------------------------------------------------------------------------
# CRD install targets
# ---------------------------------------------------------------------------
.PHONY: install-knative
install-knative: ## Install Knative Serving CRDs
	$(call apply-with-retry,$(KNATIVE_SERVING_CRDS))
	$(call wait-established,services.serving.knative.dev)

.PHONY: install-cnpg
install-cnpg: ## Install CloudNativePG CRDs
	$(call apply-with-retry,$(CNPG_CRDS))
	$(call wait-established,clusters.postgresql.cnpg.io poolers.postgresql.cnpg.io scheduledbackups.postgresql.cnpg.io objectstores.barmancloud.cnpg.io)

.PHONY: install-monitoring
install-monitoring: ## Install Prometheus Operator CRDs (PodMonitor, PrometheusRule)
	$(call apply-with-retry,$(MONITORING_CRDS))
	$(call wait-established,podmonitors.monitoring.coreos.com prometheusrules.monitoring.coreos.com)

.PHONY: install-flagger
install-flagger: ## Install Flagger CRDs
	$(call apply-with-retry,$(FLAGGER_CRDS))
	$(call wait-established,canaries.flagger.app)

.PHONY: install-kafka
install-kafka: ## Install Kafka (KafkaSource) CRDs
	$(call apply-with-retry,$(KAFKA_SOURCE_CRDS))
	$(call wait-established,kafkasources.sources.knative.dev)

.PHONY: install-eventing
install-eventing: ## Install Knative Eventing CRDs (Broker, Trigger)
	$(call apply-with-retry,$(EVENTING_CRDS))
	$(call wait-established,brokers.eventing.knative.dev triggers.eventing.knative.dev)

.PHONY: install-dragonfly
install-dragonfly: ## Install DragonflyDB CRDs
	$(call apply-with-retry,$(DRAGONFLY_CRDS))
	$(call wait-established,dragonflies.dragonflydb.io)

.PHONY: install-object-bucket
install-object-bucket: ## Install ObjectBucketClaim + ObjectBucket CRDs (Rook/Ceph bucket provisioning)
	$(call apply-with-retry,$(OBJECT_BUCKET_CRDS))
	$(call wait-established,objectbucketclaims.objectbucket.io objectbuckets.objectbucket.io)

.PHONY: install-kyverno
install-kyverno: ## Install Kyverno (CRDs + admission/background/cleanup/reports controllers)
	helm repo add --force-update kyverno https://kyverno.github.io/kyverno/
	helm repo update kyverno > /dev/null
	helm upgrade --install kyverno kyverno/kyverno \
		--version $(KYVERNO_CHART_VERSION) \
		--namespace kyverno \
		--create-namespace \
		--wait \
		--timeout 10m
	$(call wait-kyverno-webhook)

.PHONY: install-all-crds
install-all-crds: install-knative install-cnpg install-monitoring install-flagger install-kafka install-eventing install-dragonfly install-object-bucket ## Install all CRDs

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
	@# The app chart resolves its ksvc dependency against the local library chart via
	@# hack/lint-app.sh, which rewrites Chart.yaml/Chart.lock in place and always
	@# restores them on exit (even on failure), so the tree stays unchanged.
	hack/lint-app.sh helm lint charts/app/ksvc
	@set -e; for example in examples/*/; do \
		[ -f "$$example/Chart.yaml" ] || continue; \
		echo "--- Linting $$example ---"; \
		helm dependency build "$$example"; \
		helm lint "$$example"; \
	done

.PHONY: test
test: ## Run helm unit tests
	helm dependency build charts/library/ksvc/test-chart
	helm unittest charts/library/ksvc/test-chart

.PHONY: docs
docs: ## Regenerate charts/library/ksvc/README.md from values.yaml with helm-docs
	@# Runs the pinned helm-docs image; scans only the library chart and skips
	@# the test-chart wrapper and anything else listed in .helmdocsignore.
	docker run --rm \
		--volume "$(CURDIR):/helm-docs" \
		--workdir /helm-docs \
		--user "$(shell id -u):$(shell id -g)" \
		jnorwood/helm-docs:$(HELM_DOCS_VERSION) \
		--chart-search-root=charts/library \
		--template-files=README.md.gotmpl

.PHONY: update-locks
update-locks: ## Refresh Chart.lock files (test-chart, examples, app chart) from current sources
	helm dependency update charts/library/ksvc/test-chart
	@set -e; for example in examples/*/; do \
		[ -f "$$example/Chart.yaml" ] || continue; \
		echo "--- Updating $$example ---"; \
		helm dependency update "$$example"; \
	done
	helm dependency update charts/app/ksvc

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
