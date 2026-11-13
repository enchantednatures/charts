#!/usr/bin/env bash
# Install only the Redpanda CRDs (no controller).
#
# The operator chart installs CRDs from the operator image rather than shipping
# them as chart templates, and the upstream repository no longer publishes raw
# CRD manifests. Run the same image's `crd` command in a short-lived Job so this
# target stays CRD-only.
set -euo pipefail

operator_version="${REDPANDA_OPERATOR_VERSION:-26.2.5}"
image="${REDPANDA_OPERATOR_IMAGE:-docker.redpanda.com/redpandadata/redpanda-operator:v${operator_version}}"
namespace="${REDPANDA_CRD_NAMESPACE:-redpanda-system}"
job="${REDPANDA_CRD_JOB:-redpanda-crd-install}"

crash_report() {
  local rc=$?
  if ((rc != 0)); then
    kubectl -n "$namespace" describe "job/$job" || true
    kubectl -n "$namespace" logs "job/$job" --tail=100 || true
  fi
  exit "$rc"
}
trap crash_report EXIT

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$namespace" delete job "$job" --ignore-not-found --wait=true >/dev/null

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $job
  namespace: $namespace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $job
rules:
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["create", "get", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $job
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $job
subjects:
  - kind: ServiceAccount
    name: $job
    namespace: $namespace
---
apiVersion: batch/v1
kind: Job
metadata:
  name: $job
  namespace: $namespace
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: $job
      containers:
        - name: crd-installation
          image: $image
          imagePullPolicy: IfNotPresent
          command: ["/redpanda-operator"]
          args: ["crd"]
          securityContext:
            allowPrivilegeEscalation: false
EOF

kubectl -n "$namespace" wait --for=condition=complete "job/$job" --timeout=300s
kubectl wait --for=condition=Established \
  crd/redpandas.cluster.redpanda.com \
  crd/topics.cluster.redpanda.com \
  crd/users.cluster.redpanda.com \
  --timeout=300s
