#!/usr/bin/env python3
"""Exercise charts/library/ksvc/values.schema.json in both directions.

CI previously only proved that the example values *pass* the schema. This test
also proves that the schema *rejects* invalid values, so a relaxed or broken
schema cannot silently accept consumer mistakes.

Run:
    python3 hack/test-values-schema.py
"""
from __future__ import annotations

import copy
import glob
import json
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "charts" / "library" / "ksvc" / "values.schema.json"
EXAMPLE_GLOB = str(ROOT / "examples" / "*" / "values.yaml")


def load_yaml(path: str | Path) -> dict:
    with open(path, encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a YAML mapping, got {type(data).__name__}")
    return data


BASE_VALUES = load_yaml(ROOT / "examples" / "minimal" / "values.yaml")


def mutate(path: list[str], value: object) -> dict:
    """Return a deep copy of the minimal example with one value replaced."""
    values = copy.deepcopy(BASE_VALUES)
    node = values
    for key in path[:-1]:
        child = node.setdefault(key, {})
        if not isinstance(child, dict):
            raise TypeError(f"path {path}: {key} is not a mapping")
        node = child
    node[path[-1]] = value
    return values


# (description, values, substring expected in at least one validation error)
NEGATIVE_CASES: list[tuple[str, dict, str]] = [
    ("services is required", {}, "'services' is a required property"),
    (
        "unknown top-level key",
        mutate(["unexpected"], True),
        "Additional properties are not allowed",
    ),
    (
        "services must be a map",
        {"services": []},
        "is not of type 'object'",
    ),
    (
        "service entry must define image",
        {"services": {"api": {}}},
        "'image' is a required property",
    ),
    (
        "image must define repository",
        {"services": {"api": {"image": {}}}},
        "'repository' is a required property",
    ),
    (
        "unknown service field",
        mutate(["services", "api", "unexpected"], True),
        "Additional properties are not allowed",
    ),
    (
        "invalid workload type",
        mutate(["services", "api", "workload", "type"], "Job"),
        "'Job' is not one of ['Knative', 'Deployment']",
    ),
    (
        "invalid image pull policy",
        mutate(["services", "api", "image", "pullPolicy"], "Sometimes"),
        "'Sometimes' is not one of ['Always', 'IfNotPresent', 'Never']",
    ),
    (
        "negative minScale",
        mutate(["services", "api", "scaling", "minScale"], -1),
        "is less than the minimum of 0",
    ),
    (
        "unsupported postgres major version",
        mutate(["postgres", "version"], "13"),
        "'13' is not one of ['14', '15', '16', '17']",
    ),
    (
        "postgres instances below minimum",
        mutate(["postgres", "instances"], 0),
        "is less than the minimum of 1",
    ),
    (
        "postgres instances above maximum",
        mutate(["postgres", "instances"], 17),
        "is greater than the maximum of 16",
    ),
    (
        "dragonfly replicas above maximum",
        mutate(["dragonfly", "replicas"], 17),
        "is greater than the maximum of 16",
    ),
    (
        "dragonfly enabled must be boolean",
        mutate(["dragonfly", "enabled"], "yes"),
        "'yes' is not of type 'boolean'",
    ),
    (
        "object bucket entry must define storageClassName",
        mutate(["objectBuckets", "assets"], {}),
        "'storageClassName' is a required property",
    ),
    (
        "ping source key must be a DNS label",
        mutate(["pingsources", "Bad_Key"], {"sink": "api"}),
        "does not match",
    ),
    (
        "ping source must define sink",
        mutate(["pingsources", "nightly"], {"schedule": "0 * * * *"}),
        "'sink' is a required property",
    ),
    (
        "unknown broker field",
        mutate(["kafka", "broker", "unexpected"], True),
        "Additional properties are not allowed",
    ),
    (
        "broker bootstrap servers must not be empty",
        mutate(["kafka", "broker", "config", "bootstrapServers"], []),
        "should be non-empty",
    ),
    (
        "trigger must define subscriber",
        mutate(["kafka", "triggers", "order"], {}),
        "'subscriber' is a required property",
    ),
    (
        "unknown trigger field",
        mutate(["kafka", "triggers", "order"], {"subscriber": "api", "unexpected": True}),
        "Additional properties are not allowed",
    ),
    (
        "invalid trigger backoff policy",
        mutate(
            ["kafka", "triggers", "order"],
            {"subscriber": "api", "delivery": {"backoffPolicy": "random"}},
        ),
        "'random' is not one of ['linear', 'exponential']",
    ),
    (
        "trigger dlq maxScale below minimum",
        mutate(
            ["kafka", "triggers", "order"],
            {"subscriber": "api", "dlq": {"scaling": {"maxScale": 0}}},
        ),
        "is less than the minimum of 1",
    ),
    (
        "unknown kafka source net field",
        mutate(
            ["kafka", "sources", "events"],
            {"topic": "events", "net": {"unexpected": True}},
        ),
        "Additional properties are not allowed",
    ),
    (
        "invalid kafka source sasl mechanism",
        mutate(
            ["kafka", "sources", "events"],
            {"topic": "events", "net": {"sasl": {"mechanism": "SCRAM"}}},
        ),
        "'SCRAM' is not one of ['PLAIN', 'SCRAM-SHA-256', 'SCRAM-SHA-512']",
    ),
    (
        "kafka source net tls enabled must be boolean",
        mutate(
            ["kafka", "sources", "events"],
            {"topic": "events", "net": {"tls": {"enabled": "yes"}}},
        ),
        "'yes' is not of type 'boolean'",
    ),
]


def main() -> int:
    with open(SCHEMA_PATH, encoding="utf-8") as handle:
        schema = json.load(handle)

    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    failures = 0

    example_paths = sorted(glob.glob(EXAMPLE_GLOB))
    if not example_paths:
        print("FAIL: no examples/*/values.yaml files found", file=sys.stderr)
        return 1

    for path in example_paths:
        errors = sorted(validator.iter_errors(load_yaml(path)), key=lambda e: list(e.path))
        if errors:
            failures += 1
            print(f"FAIL: {path} should validate but does not:", file=sys.stderr)
            for error in errors:
                print(f"  - {error.message}", file=sys.stderr)
        else:
            print(f"PASS: {Path(path).relative_to(ROOT)} validates")

    for description, values, expected in NEGATIVE_CASES:
        errors = sorted(validator.iter_errors(values), key=lambda e: list(e.path))
        if not errors:
            failures += 1
            print(f"FAIL: {description}: schema accepted invalid values", file=sys.stderr)
            continue
        if not any(expected in error.message for error in errors):
            failures += 1
            print(
                f"FAIL: {description}: expected an error containing {expected!r}",
                file=sys.stderr,
            )
            for error in errors:
                print(f"  - {error.message}", file=sys.stderr)
            continue
        print(f"PASS: {description} is rejected")

    if failures:
        print(f"test-values-schema: {failures} failure(s)", file=sys.stderr)
        return 1

    print(
        f"test-values-schema: OK "
        f"({len(example_paths)} examples, {len(NEGATIVE_CASES)} negative cases)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
