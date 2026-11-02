# Vendored kubeconform schemas

`kubeconform` resolves CRD schemas from the Datree CRDs catalog. The catalog
does not publish a `KafkaSource` schema for
`sources.knative.dev/v1beta1`, so a rendered `KafkaSource` would fail
validation. This directory vendors only that missing schema; every other CRD
is still resolved from the catalog.

The JSON schema is derived from the upstream CRD in
[`knative-extensions/eventing-kafka-broker`](https://github.com/knative-extensions/eventing-kafka-broker)
at tag `knative-v1.17.0`, which matches `KAFKA_EVENTING_VERSION` in the
`Makefile`. The upstream CRD is Apache-2.0 licensed; that license applies to
the derived file in this directory.

Owner: repository maintainers. Tracking issue: #84.

## Regenerating

Replace the URL if `KAFKA_EVENTING_VERSION` advances, then run:

```bash
python3 - <<'PY'
import json
import pathlib
import urllib.request
import yaml

url = "https://raw.githubusercontent.com/knative-extensions/eventing-kafka-broker/knative-v1.17.0/control-plane/config/eventing-kafka-broker/100-source/100-kafka-source.yaml"
with urllib.request.urlopen(url) as response:
    crd = yaml.safe_load(response.read())

versions = {version["name"]: version for version in crd["spec"]["versions"]}
schema = versions["v1beta1"]["schema"]["openAPIV3Schema"]

def close_objects(node):
    if isinstance(node, dict):
        if node.get("type") == "object" and "properties" in node and "additionalProperties" not in node:
            node["additionalProperties"] = False
        for value in node.values():
            close_objects(value)
    elif isinstance(node, list):
        for value in node:
            close_objects(value)

close_objects(schema)
path = pathlib.Path("hack/kubeconform-schemas/sources.knative.dev/kafkasource_v1beta1.json")
path.write_text(json.dumps(schema, indent=2) + "\n", encoding="utf-8")
PY
```

Adding `additionalProperties: false` to every object that declares
`properties` mirrors the catalog's generated schemas, so `kubeconform -strict`
still rejects unknown fields.
