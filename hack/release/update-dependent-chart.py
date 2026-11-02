#!/usr/bin/env python3
"""Update a dependent chart's own version and block-style dependency pins.

The release workflow bumps an application chart after a library release. The
Chart.yaml files in this repository use a plain block-style ``dependencies:``
list, so this helper edits only the exact dependency entries it is given and
leaves the rest of the file byte-for-byte intact.

Usage:
    python3 hack/release/update-dependent-chart.py charts/app/ksvc/Chart.yaml \
      --bump patch --dependency ksvc=1.0.0
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_DEPENDENCIES = re.compile(r"^dependencies:\s*$")
_TOP_LEVEL = re.compile(r"^\S")
_LIST_ITEM_NAME = re.compile(r"^(\s*)-\s+name:\s*(\S+)\s*$")
_VERSION_FIELD = re.compile(r"^(\s+)version:\s*(.+?)\s*$")
_TOP_LEVEL_VERSION = re.compile(r"^version:\s*(\S+)\s*$")
_PATCH_VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def fail(message: str) -> None:
    print(f"update-dependent-chart: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_dependency(value: str) -> tuple[str, str]:
    name, separator, version = value.partition("=")
    if not separator or not name or not version:
        fail(f"--dependency must be name=version (got '{value}')")
    return name, version


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("chart_yaml", help="Chart.yaml to update in place")
    parser.add_argument(
        "--dependency",
        action="append",
        default=[],
        metavar="NAME=VERSION",
        help="dependency pin to update (repeatable)",
    )
    parser.add_argument("--bump", choices=["patch"], help="bump the chart's own version")
    args = parser.parse_args()

    wanted = dict(parse_dependency(value) for value in args.dependency)
    path = Path(args.chart_yaml)
    if not path.is_file():
        fail(f"chart metadata not found: {path}")

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    updated: set[str] = set()
    in_dependencies = False
    current_dependency: str | None = None
    chart_version_line: int | None = None

    for index, line in enumerate(lines):
        stripped = line.rstrip("\n")

        if chart_version_line is None:
            match = _TOP_LEVEL_VERSION.match(stripped)
            if match:
                chart_version_line = index

        if _DEPENDENCIES.match(stripped):
            in_dependencies = True
            current_dependency = None
            continue

        if not in_dependencies:
            continue

        if _TOP_LEVEL.match(stripped) and not stripped.startswith("-"):
            in_dependencies = False
            current_dependency = None
            continue

        item = _LIST_ITEM_NAME.match(stripped)
        if item:
            current_dependency = item.group(2)
            continue

        field = _VERSION_FIELD.match(stripped)
        if field and current_dependency in wanted:
            newline = "\n" if line.endswith("\n") else ""
            lines[index] = f"{field.group(1)}version: {wanted[current_dependency]}{newline}"
            updated.add(current_dependency)

    missing = sorted(set(wanted) - updated)
    if missing:
        fail(f"{path}: dependency entries not found: {', '.join(missing)}")

    if args.bump == "patch":
        if chart_version_line is None:
            fail(f"{path}: no top-level version field to bump")
        match = _TOP_LEVEL_VERSION.match(lines[chart_version_line].rstrip("\n"))
        assert match is not None
        old_version = match.group(1)
        patch_match = _PATCH_VERSION.match(old_version)
        if not patch_match:
            fail(f"{path}: cannot patch-bump non-stable version '{old_version}'")
        new_version = ".".join(
            (
                patch_match.group(1),
                patch_match.group(2),
                str(int(patch_match.group(3)) + 1),
            )
        )
        newline = "\n" if lines[chart_version_line].endswith("\n") else ""
        lines[chart_version_line] = f"version: {new_version}{newline}"
        print(f"{path}: chart version {old_version} -> {new_version}")

    for name in sorted(updated):
        print(f"{path}: dependency {name} -> {wanted[name]}")

    path.write_text("".join(lines), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
