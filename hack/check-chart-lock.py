#!/usr/bin/env python3
"""Verify a chart's committed Chart.lock against its Chart.yaml.

This is the dependency-free, structural half of the lock-consistency gate. It
catches the common drift where a chart's own dependency pin is bumped without
regenerating Chart.lock. Range constraints are resolved by
``helm dependency build`` in ``hack/check-lock-consistency.sh``; here we verify
the fields that must match literally and that a lock exists whenever the chart
declares dependencies.

Usage:
    python3 hack/check-chart-lock.py <chart-dir>
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_DEPENDENCIES_KEY = re.compile(r"^dependencies:\s*$")
_TOP_LEVEL_KEY = re.compile(r"^\S")
_LIST_ITEM_NAME = re.compile(r"^\s*-\s+name:\s*(\S+)\s*$")
_ENTRY_FIELD = re.compile(r"^\s+(name|version|repository):\s*(.+?)\s*$")
# Exact semver pins only. A range (">=1.0.0", "1.2.x", "^1.0.0", ...) is left
# to `helm dependency build`, which resolves it against the real repositories.
_EXACT_VERSION = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")


def parse_dependencies(path: Path) -> list[dict[str, str]]:
    """Parse the block-style dependencies list used by these charts."""
    dependencies: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    in_dependencies = False

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue

        if _DEPENDENCIES_KEY.match(line):
            in_dependencies = True
            continue

        if not in_dependencies:
            continue

        item = _LIST_ITEM_NAME.match(line)
        if item:
            current = {"name": item.group(1).strip("\"'")}
            dependencies.append(current)
            continue

        if _TOP_LEVEL_KEY.match(line) and not line.startswith("-"):
            break

        field = _ENTRY_FIELD.match(line)
        if field and current is not None:
            current[field.group(1)] = field.group(2).strip("\"'")

    return dependencies


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("chart_dir", help="chart directory containing Chart.yaml")
    args = parser.parse_args()

    chart_dir = Path(args.chart_dir)
    chart_yaml = chart_dir / "Chart.yaml"
    chart_lock = chart_dir / "Chart.lock"

    if not chart_yaml.is_file():
        fail(f"{chart_yaml}: file not found")

    declared = parse_dependencies(chart_yaml)
    if not declared:
        if chart_lock.is_file() and parse_dependencies(chart_lock):
            fail(f"{chart_lock} declares dependencies but {chart_yaml} has none")
        if chart_lock.is_file():
            print(f"{chart_dir}: no dependencies declared; ignoring Chart.lock")
        else:
            print(f"{chart_dir}: no dependencies declared")
        return 0

    if not chart_lock.is_file():
        fail(f"{chart_yaml} declares dependencies but {chart_lock} is missing")

    locked = {dep["name"]: dep for dep in parse_dependencies(chart_lock)}

    errors: list[str] = []
    for dependency in declared:
        name = dependency.get("name")
        if not name:
            errors.append(f"{chart_yaml}: dependency entry is missing a name")
            continue

        lock_entry = locked.get(name)
        if lock_entry is None:
            errors.append(f"{chart_lock}: missing entry for dependency '{name}'")
            continue

        for field in ("repository", "version"):
            wanted = dependency.get(field)
            actual = lock_entry.get(field)
            if wanted is None:
                errors.append(f"{chart_yaml}: dependency '{name}' is missing {field}")
            elif actual is None:
                errors.append(f"{chart_lock}: dependency '{name}' is missing {field}")
            elif field == "repository" and wanted != actual:
                errors.append(
                    f"{chart_lock}: dependency '{name}' repository is '{actual}' "
                    f"but Chart.yaml pins '{wanted}'"
                )
            elif field == "version" and _EXACT_VERSION.match(wanted) and wanted != actual:
                errors.append(
                    f"{chart_lock}: dependency '{name}' version is '{actual}' "
                    f"but Chart.yaml pins '{wanted}'"
                )

    for name in sorted(set(locked) - {dep.get("name") for dep in declared}):
        errors.append(f"{chart_lock}: dependency '{name}' is not declared in Chart.yaml")

    if errors:
        for message in errors:
            print(f"::error::{message}", file=sys.stderr)
        return 1

    print(f"{chart_dir}: Chart.lock matches Chart.yaml")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
