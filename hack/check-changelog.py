#!/usr/bin/env python3
"""Verify CHANGELOG.md covers the chart product line being released.

The changelog is curated per product line, not per patch. Both charts declare
`appVersion: 1.0.0`, so the changelog must have a `1.0.0` section and document
that exact chart patch/prerelease versions are covered by the generated GitHub
Release notes. This check keeps that contract from silently rotting.

Run:
    python3 hack/check-changelog.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"
CHARTS = (
    ROOT / "charts" / "library" / "ksvc" / "Chart.yaml",
    ROOT / "charts" / "app" / "ksvc" / "Chart.yaml",
)
BASE_VERSION = re.compile(r"^(\d+\.\d+\.\d+)")
GENERATED_NOTES = re.compile(r"generated\s+GitHub\s+Release\s+notes", re.IGNORECASE)

errors: list[str] = []


def error(message: str) -> None:
    errors.append(message)


def section_pattern(version: str) -> re.Pattern[str]:
    return re.compile(
        rf"^##\s+\[?{re.escape(version)}\]?(?:\s|$)",
        re.MULTILINE,
    )


def chart_product_version(path: Path) -> str | None:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        error(f"{path.relative_to(ROOT)}: cannot read chart metadata: {exc}")
        return None
    if not isinstance(data, dict):
        error(f"{path.relative_to(ROOT)}: Chart.yaml must be a YAML mapping")
        return None
    app_version = data.get("appVersion")
    if not isinstance(app_version, str):
        error(f"{path.relative_to(ROOT)}: missing string appVersion")
        return None
    match = BASE_VERSION.match(app_version)
    if not match:
        error(f"{path.relative_to(ROOT)}: appVersion {app_version!r} is not semver")
        return None
    return match.group(1)


def main() -> int:
    try:
        changelog = CHANGELOG.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"check-changelog: cannot read CHANGELOG.md: {exc}", file=sys.stderr)
        return 1

    versions = {path: chart_product_version(path) for path in CHARTS}
    for path, version in versions.items():
        if version is None:
            continue
        if not section_pattern(version).search(changelog):
            error(
                f"CHANGELOG.md has no '## [{version}]' section for "
                f"{path.relative_to(ROOT)} appVersion"
            )

    if not GENERATED_NOTES.search(changelog):
        error(
            "CHANGELOG.md must document that exact chart patch/prerelease "
            "versions are covered by generated GitHub Release notes"
        )

    if "MIGRATION.md" not in changelog:
        error("CHANGELOG.md must link the migration guide (MIGRATION.md)")

    if errors:
        for message in errors:
            print(f"FAIL: {message}", file=sys.stderr)
        print(
            f"check-changelog: {len(errors)} error(s); update CHANGELOG.md and retry",
            file=sys.stderr,
        )
        return 1

    print("check-changelog: OK (product line and generated release notes documented)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
