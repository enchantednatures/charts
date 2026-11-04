#!/usr/bin/env bash
#
# Live e2e for Ceph RGW bucket notifications:
#   loop device OSD -> Rook CephCluster -> CephObjectStore -> bucket
#   StorageClass -> Strimzi Kafka + topic -> ObjectBucketClaim -> S3 put
#   -> CephBucketNotification -> Kafka topic.
#
# The Kind node has no real disks, so this script creates a loop device inside
# the node before installing Rook. It expects a fresh Kind cluster named by
# KIND_CLUSTER (the integration workflow creates it).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

KIND_CLUSTER="${KIND_CLUSTER:-obn-e2e}"
NAMESPACE="${NAMESPACE:-test-ns}"
RELEASE="${RELEASE:-obn-e2e}"
ROOK_CHART_VERSION="${ROOK_CHART_VERSION:-1.21.1}"
LOOP_SIZE="${LOOP_SIZE:-8G}"

say() { printf '\n==> %s\n' "$*"; }

diagnostics() {
  set +e
  echo ""
  echo "=== diagnostics ==="
  kubectl get cephcluster,cephobjectstore,cephbuckettopic,cephbucketnotification,objectbucketclaim -A -o wide || true
  kubectl -n "$NAMESPACE" get kafka,kafkatopic,objectbucketclaim,pods -o wide || true
  kubectl -n rook-ceph get pods -o wide || true
  for pod in $(kubectl -n rook-ceph get pods -l app=rook-ceph-osd-prepare -o name); do
    kubectl -n rook-ceph logs "$pod" --tail=200 || true
  done
  for pod in $(kubectl -n rook-ceph get pods -l app=rook-ceph-osd -o name); do
    kubectl -n rook-ceph describe "$pod" | tail -60 || true
    kubectl -n rook-ceph logs "$pod" --tail=200 || true
  done
  mon="$(kubectl -n rook-ceph get pods -l app=rook-ceph-mon -o name | head -1)"
  if [ -n "$mon" ]; then
    kubectl -n rook-ceph exec "$mon" -- ceph -s || true
  fi
  kubectl -n rook-ceph logs deploy/rook-ceph-operator --tail=120 || true
  kubectl -n "$NAMESPACE" get objectbucketclaim -o name | xargs -r -n1 kubectl -n "$NAMESPACE" describe || true
  if kubectl -n "$NAMESPACE" get pod s3-put >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" logs s3-put || true
  fi
  if kubectl -n "$NAMESPACE" get pod kafka-consume >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" logs kafka-consume || true
  fi
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then diagnostics; fi; exit "$rc"' EXIT

wait_for_phase() {
  local resource=$1 name=$2 namespace=$3 expected=$4 timeout=$5
  local deadline=$((SECONDS + timeout))
  local phase=""
  while ((SECONDS < deadline)); do
    phase="$(kubectl -n "$namespace" get "$resource" "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$phase" == "$expected" ]]; then
      echo "  $resource/$name is $expected"
      return 0
    fi
    sleep 10
  done
  echo "timed out waiting for $resource/$name to be $expected (last phase: ${phase:-unknown})" >&2
  return 1
}

wait_for_pod_phase() {
  local name=$1 namespace=$2 expected=$3 timeout=$4
  local deadline=$((SECONDS + timeout))
  local phase=""
  while ((SECONDS < deadline)); do
    phase="$(kubectl -n "$namespace" get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$phase" == "$expected" ]]; then
      return 0
    fi
    sleep 5
  done
  echo "timed out waiting for pod/$name to be $expected (last phase: ${phase:-unknown})" >&2
  return 1
}

say "Creating a loop device inside the Kind node ($KIND_CLUSTER)"
node="$(kind get nodes --name "$KIND_CLUSTER" | head -1)"
test -n "$node"
docker exec "$node" bash -c "
  set -euo pipefail
  if [ ! -f /tmp/ceph-osd.img ]; then
    truncate -s '$LOOP_SIZE' /tmp/ceph-osd.img
  fi
  loop=\$(losetup -j /tmp/ceph-osd.img | cut -d: -f1 | head -1 || true)
  if [ -z \"\$loop\" ]; then
    loop=\$(losetup -f --show /tmp/ceph-osd.img)
  fi
  echo \"\$loop\" > /tmp/ceph-loop
  echo \"loop device: \$loop\"
"

say "Installing Knative Serving, Rook, and ObjectBucketClaim CRDs"
# The example renders Knative Services, but the notification path does not
# need the Serving controller; CRDs are enough for the install to apply.
# The Rook chart is installed with crds.enabled=false so it does not try to
# adopt these raw-applied CRDs.
make install-knative
make install-rook-crds
make install-object-bucket

say "Installing the Rook operator ($ROOK_CHART_VERSION)"
helm repo add rook-release https://charts.rook.io/release >/dev/null 2>&1 || true
helm repo update rook-release >/dev/null
helm upgrade --install rook-ceph rook-release/rook-ceph \
  --namespace rook-ceph \
  --create-namespace \
  --version "$ROOK_CHART_VERSION" \
  --set crds.enabled=false \
  --set allowLoopDevices=true \
  --wait \
  --timeout 10m
kubectl -n rook-ceph rollout status deploy/rook-ceph-operator --timeout=300s

say "Creating the single-node CephCluster"
loop_device="$(docker exec "$node" cat /tmp/ceph-loop)"
# Rook can only use loop devices through the explicit `devices` list.
sed "s|/dev/loop0|${loop_device}|g" \
  test/e2e/object-bucket-notifications/rook-ceph-cluster.yaml | kubectl apply -f -
wait_for_phase cephcluster rook-ceph rook-ceph Ready 1200

say "Creating the CephObjectStore and bucket StorageClass"
kubectl apply -f test/e2e/object-bucket-notifications/ceph-object-store.yaml
wait_for_phase cephobjectstore ceph-objectstore rook-ceph Ready 900
kubectl apply -f test/e2e/object-bucket-notifications/ceph-bucket-storageclass.yaml

say "Installing the Strimzi operator"
hack/install-strimzi-operator.sh

say "Installing the object-bucket-notifications example"
helm dependency build examples/object-bucket-notifications >/dev/null
helm upgrade --install "$RELEASE" examples/object-bucket-notifications \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set kafka.cluster.replicas=1 \
  --set kafka.cluster.storage.size=5Gi \
  --set kafka.cluster.storage.storageClassName=standard \
  --set kafka.cluster.resources.requests.cpu=100m \
  --set kafka.cluster.resources.requests.memory=512Mi \
  --set kafka.cluster.resources.limits.cpu=1 \
  --set kafka.cluster.resources.limits.memory=1Gi \
  --timeout 15m

say "Waiting for Kafka and the notification topics"
kubectl -n "$NAMESPACE" wait --for=condition=Ready kafka --all --timeout=15m
kubectl -n "$NAMESPACE" wait --for=condition=Ready kafkatopic --all --timeout=5m

say "Waiting for the ObjectBucketClaim to bind"
obc="$(kubectl -n "$NAMESPACE" get objectbucketclaim -o jsonpath='{.items[0].metadata.name}')"
test -n "$obc"
wait_for_phase objectbucketclaim "$obc" "$NAMESPACE" Bound 600

say "Waiting for Rook to provision the bucket topic and notification"
wait_for_phase cephbuckettopic "${RELEASE}-uploads-put" "$NAMESPACE" Ready 300
wait_for_phase cephbucketnotification "${RELEASE}-uploads-put" "$NAMESPACE" Ready 300

access_key="$(kubectl -n "$NAMESPACE" get secret "$obc" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)"
secret_key="$(kubectl -n "$NAMESPACE" get secret "$obc" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)"
bucket_host="$(kubectl -n "$NAMESPACE" get configmap "$obc" -o jsonpath='{.data.BUCKET_HOST}')"
bucket_port="$(kubectl -n "$NAMESPACE" get configmap "$obc" -o jsonpath='{.data.BUCKET_PORT}')"
bucket_name="$(kubectl -n "$NAMESPACE" get configmap "$obc" -o jsonpath='{.data.BUCKET_NAME}')"
test -n "$access_key" && test -n "$secret_key" && test -n "$bucket_host" && test -n "$bucket_port" && test -n "$bucket_name"

say "Uploading an object that matches the notification filter (uploads/)"
kubectl -n "$NAMESPACE" delete pod s3-put --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" run s3-put \
  --image=amazon/aws-cli:latest \
  --restart=Never \
  --command -- \
  env "AWS_ACCESS_KEY_ID=$access_key" "AWS_SECRET_ACCESS_KEY=$secret_key" AWS_DEFAULT_REGION=us-east-1 \
  sh -c "printf 'bucket-notification-e2e' > /tmp/object.txt && aws --endpoint-url http://${bucket_host}:${bucket_port} s3 cp /tmp/object.txt s3://${bucket_name}/uploads/bucket-notification-e2e.txt"
wait_for_pod_phase s3-put "$NAMESPACE" Succeeded 300

say "Consuming the notification topic"
bootstrap="${RELEASE}-kafka-kafka-bootstrap:9092"
topic="${RELEASE}-uploads-put"
kubectl -n "$NAMESPACE" delete pod kafka-consume --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" run kafka-consume \
  --image=apache/kafka:3.9.1 \
  --restart=Never \
  --command -- \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server "$bootstrap" \
  --topic "$topic" \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 180000
wait_for_pod_phase kafka-consume "$NAMESPACE" Succeeded 240

logs="$(kubectl -n "$NAMESPACE" logs kafka-consume)"
echo "$logs"
grep -q 's3:ObjectCreated:Put' <<<"$logs"
grep -q 'bucket-notification-e2e.txt' <<<"$logs"

echo ""
echo "Object bucket notification e2e passed: S3 put -> CephBucketNotification -> $topic"
