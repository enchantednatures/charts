#!/usr/bin/env python3
"""Keep README.md's Requirements section honest.

The section documents operator/CRD prerequisites, Makefile versions, and chart
defaults. None of those are generated, so they drift silently unless checked.
This script is deliberately source-driven: it reads the templates, Makefile,
values.yaml, and Chart.yaml files and fails when the README no longer agrees.

Run:
    python3 hack/check-requirements-docs.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

import yaml

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
MAKEFILE = ROOT / "Makefile"
TEMPLATES = ROOT / "charts" / "library" / "ksvc" / "templates"
VALUES = ROOT / "charts" / "library" / "ksvc" / "values.yaml"
LOADER = ROOT / "charts" / "library" / "ksvc" / "templates" / "loader" / "_generate.tpl"
CHARTS = [
    ROOT / "charts" / "library" / "ksvc" / "Chart.yaml",
    ROOT / "charts" / "app" / "ksvc" / "Chart.yaml",
]
EXAMPLES = sorted((ROOT / "examples").glob("*/Chart.yaml"))

# Kinds that are built into Kubernetes (or rendered by the chart itself) and
# therefore do not require an operator prerequisite.
CORE_KINDS = {"Deployment", "Service", "Secret", "PodDisruptionBudget"}

# Kinds referenced by the chart but not emitted as a top-level resource.
REFERENCED_KINDS = {"ClusterImageCatalog"}

VERSION_VARS = {
    "KNATIVE_VERSION": "Knative Serving/Eventing",
    "CNPG_RELEASE": "CNPG",
    "KAFKA_EVENTING_VERSION": "eventing-kafka",
    "KYVERNO_CHART_VERSION": "Kyverno",
}

errors: list[str] = []


def error(message: str) -> None:
    errors.append(message)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_rendered_kinds(readme: str) -> None:
    kinds: set[str] = set()
    for path in sorted(TEMPLATES.rglob("*.tpl")):
        for line in read(path).splitlines():
            match = re.match(r"^kind:\s*([A-Za-z][A-Za-z0-9]*)\s*$", line)
            if match:
                kinds.add(match.group(1))
            elif line.startswith("kind:"):
                error(
                    f"{path.relative_to(ROOT)}: top-level kind is not a literal; "
                    "teach check-requirements-docs.py how to verify it"
                )

    for kind in sorted(kinds - CORE_KINDS):
        if f"`{kind}`" not in readme:
            error(f"README Requirements does not mention rendered kind `{kind}`")

    for kind in sorted(REFERENCED_KINDS):
        if f"`{kind}`" not in readme:
            error(f"README Requirements does not mention referenced kind `{kind}`")


def makefile_targets(makefile: str) -> dict[str, list[str]]:
    targets: dict[str, list[str]] = {}
    current: str | None = None
    for line in makefile.splitlines():
        target = re.match(r"^(install-[a-z0-9-]+):", line)
        if target:
            current = target.group(1)
            targets[current] = []
            continue
        if re.match(r"^[A-Za-z0-9_.-]+:", line):
            current = None
            continue
        if current is not None:
            targets[current].append(line)
    return targets


def check_install_targets(readme: str, makefile: str) -> None:
    targets = makefile_targets(makefile)
    if not targets:
        error("Makefile has no install-* targets to check")
        return

    # install-local and install-flux-sync are local-cluster helpers, not
    # operator installs; install-all-crds only aggregates the CRD targets.
    non_crd_targets = {"install-all-crds", "install-local", "install-flux-sync"}

    for target, body in sorted(targets.items()):
        if target in non_crd_targets or target == "install-kyverno":
            continue
        if any("helm " in line for line in body):
            error(
                f"Makefile target {target} invokes Helm; README claims only "
                "install-kyverno installs a controller"
            )

    kyverno = "\n".join(targets.get("install-kyverno", []))
    if "helm upgrade --install" not in kyverno:
        error("Makefile target install-kyverno no longer installs Kyverno via Helm")

    # Only explicit `make install-*` references are Makefile targets; script
    # paths such as hack/install-strimzi-operator.sh are not.
    referenced = set(re.findall(r"\bmake\s+(install-[a-z0-9-]+)\b", readme))
    for target in sorted(referenced):
        if target not in targets:
            error(f"README references `make {target}`, but the Makefile has no such target")


def check_versions(readme: str, makefile: str) -> None:
    for variable, description in VERSION_VARS.items():
        match = re.search(rf"^{re.escape(variable)}\s*\?=\s*(\S+)", makefile, re.MULTILINE)
        if not match:
            error(f"Makefile is missing {variable}")
            continue
        value = match.group(1)
        if f"{description} {value}" not in readme:
            error(
                f"README does not mention the {description} version pinned in "
                f"{variable} ({value})"
            )


def get_path(mapping: dict, path: list[str]) -> object:
    node: object = mapping
    for key in path:
        if not isinstance(node, dict) or key not in node:
            raise KeyError(".".join(path))
        node = node[key]
    return node


def check_defaults(readme: str) -> None:
    values = yaml.safe_load(read(VALUES))

    try:
        image_catalog = get_path(values, ["postgres", "imageCatalog", "name"])
        monitoring = get_path(values, ["postgres", "monitoring", "enabled"])
        prometheus = get_path(
            values, ["services", "api", "flagger", "metrics", "prometheusAddress"]
        )
        load_test = get_path(values, ["services", "api", "flagger", "loadTest", "webhookUrl"])
    except KeyError as exc:
        error(f"values.yaml no longer contains {exc.args[0]}")
        return

    if f"`{image_catalog}`" not in readme:
        error(f"README does not mention the default image catalog `{image_catalog}`")

    monitoring_claim = "default `true`" if monitoring is True else "default `false`"
    if monitoring_claim not in readme:
        error(
            "README does not state the postgres.monitoring.enabled default "
            f"({monitoring})"
        )

    for label, value in (("Prometheus address", prometheus), ("k6 load tester", load_test)):
        host = urlsplit(str(value)).netloc
        if host not in readme:
            error(f"README does not mention the default {label} ({host})")

    bootstrap_match = re.search(r'"bootstrapServers"\s*\(list\s+"([^"]+)"', read(LOADER))
    if not bootstrap_match:
        error("could not find the default bootstrapServers in the loader template")
    elif bootstrap_match.group(1) not in readme:
        error(
            "README does not mention the default bootstrapServers "
            f"({bootstrap_match.group(1)})"
        )


def check_kube_version(readme: str) -> None:
    constraints: dict[str, str] = {}
    for path in CHARTS:
        data = yaml.safe_load(read(path))
        constraint = data.get("kubeVersion")
        if not constraint:
            error(f"{path.relative_to(ROOT)} does not declare kubeVersion")
            continue
        constraints[str(path.relative_to(ROOT))] = str(constraint)

    for path in EXAMPLES:
        data = yaml.safe_load(read(path))
        constraint = data.get("kubeVersion")
        if not constraint:
            error(f"{path.relative_to(ROOT)} does not declare kubeVersion")
        else:
            constraints[str(path.relative_to(ROOT))] = str(constraint)

    distinct = set(constraints.values())
    if len(distinct) > 1:
        formatted = ", ".join(f"{path}={value}" for path, value in sorted(constraints.items()))
        error(f"charts disagree on kubeVersion: {formatted}")
        return

    if not distinct:
        return

    match = re.search(r">=\s*(\d+)\.(\d+)", next(iter(distinct)))
    if not match:
        error(f"cannot derive a minimum Kubernetes version from {next(iter(distinct))!r}")
        return

    documented = f"Kubernetes >= {match.group(1)}.{match.group(2)}"
    if documented not in readme:
        error(f"README does not state `{documented}`")


def main() -> int:
    readme = read(README)
    makefile = read(MAKEFILE)

    check_rendered_kinds(readme)
    check_install_targets(readme, makefile)
    check_versions(readme, makefile)
    check_defaults(readme)
    check_kube_version(readme)

    if errors:
        for message in errors:
            print(f"FAIL: {message}", file=sys.stderr)
        print(
            f"check-requirements-docs: {len(errors)} drift error(s); "
            "update README.md (or the source) and retry",
            file=sys.stderr,
        )
        return 1

    print("check-requirements-docs: OK (kinds, install targets, versions, defaults, kubeVersion)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
