#!/usr/bin/env python3
"""Validate Artifact Hub metadata in every chart's Chart.yaml.

Artifact Hub reads the chart `icon`, the `artifacthub.io/*` annotations, and
the changelog from the published OCI artifact. A malformed annotation is only
discovered after packaging, so this check fails the PR before merge.

It verifies both charts have:
  * an `icon` that points at the repository-owned SVG,
  * `artifacthub.io/category`, `artifacthub.io/license`,
    `artifacthub.io/changes`, `artifacthub.io/images`, and
    `artifacthub.io/links` annotations,
  * a `changes` annotation that is a YAML list of {kind, description} entries,
  * an `images` annotation that is a YAML list of {name, image} entries,
  * a `links` annotation that is a YAML list of {name, url} entries containing
    source, documentation, and migration links.

Run:
    python3 hack/check-artifacthub.py
"""
from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import urlsplit

import yaml

ROOT = Path(__file__).resolve().parent.parent
CHARTS = (
    ROOT / "charts" / "library" / "ksvc" / "Chart.yaml",
    ROOT / "charts" / "app" / "ksvc" / "Chart.yaml",
)
ICON = ROOT / "docs" / "icon.svg"
REQUIRED_ANNOTATIONS = (
    "artifacthub.io/category",
    "artifacthub.io/license",
    "artifacthub.io/changes",
    "artifacthub.io/images",
    "artifacthub.io/links",
)
VALID_CHANGE_KINDS = {
    "added",
    "changed",
    "deprecated",
    "fixed",
    "removed",
    "security",
}
REQUIRED_LINKS = ("source", "documentation", "migration")

errors: list[str] = []


def error(path: Path, message: str) -> None:
    errors.append(f"{path.relative_to(ROOT)}: {message}")


def load_chart(path: Path) -> dict | None:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as exc:
        error(path, f"cannot read file: {exc}")
        return None
    except yaml.YAMLError as exc:
        error(path, f"invalid YAML: {exc}")
        return None
    if not isinstance(data, dict):
        error(path, "Chart.yaml must be a YAML mapping")
        return None
    return data


def parsed_block(path: Path, annotation: str, value: object) -> object | None:
    if not isinstance(value, str) or not value.strip():
        error(path, f"{annotation} must be a non-empty YAML block")
        return None
    try:
        return yaml.safe_load(value)
    except yaml.YAMLError as exc:
        error(path, f"{annotation} is not valid YAML: {exc}")
        return None


def check_icon(path: Path, chart: dict) -> None:
    icon = chart.get("icon")
    if not isinstance(icon, str) or not icon.strip():
        error(path, "missing or empty `icon` field")
        return
    parts = urlsplit(icon)
    if parts.scheme != "https" or not parts.netloc.endswith("githubusercontent.com"):
        error(path, f"icon must be an https raw GitHub URL, got {icon!r}")
    if not parts.path.endswith(".svg"):
        error(path, f"icon must point at the repository SVG, got {icon!r}")
    if not ICON.is_file():
        error(path, f"repository icon {ICON.relative_to(ROOT)} does not exist")


def check_changes(path: Path, value: object) -> None:
    changes = parsed_block(path, "artifacthub.io/changes", value)
    if changes is None:
        return
    if not isinstance(changes, list) or not changes:
        error(path, "artifacthub.io/changes must be a non-empty YAML list")
        return
    for index, change in enumerate(changes, 1):
        if not isinstance(change, dict):
            error(path, f"artifacthub.io/changes entry {index} must be a mapping")
            continue
        kind = change.get("kind")
        description = change.get("description")
        if kind not in VALID_CHANGE_KINDS:
            error(
                path,
                f"artifacthub.io/changes entry {index} has invalid kind {kind!r}; "
                f"expected one of {sorted(VALID_CHANGE_KINDS)}",
            )
        if not isinstance(description, str) or not description.strip():
            error(
                path,
                f"artifacthub.io/changes entry {index} needs a non-empty description",
            )


def check_images(path: Path, value: object) -> None:
    images = parsed_block(path, "artifacthub.io/images", value)
    if images is None:
        return
    if not isinstance(images, list) or not images:
        error(path, "artifacthub.io/images must be a non-empty YAML list")
        return
    for index, entry in enumerate(images, 1):
        if not isinstance(entry, dict):
            error(path, f"artifacthub.io/images entry {index} must be a mapping")
            continue
        name = entry.get("name")
        image = entry.get("image")
        if not isinstance(name, str) or not name.strip():
            error(path, f"artifacthub.io/images entry {index} needs a name")
        if not isinstance(image, str) or not image.strip():
            error(path, f"artifacthub.io/images entry {index} needs an image")
        elif ":" not in image and "@sha256:" not in image:
            error(
                path,
                f"artifacthub.io/images entry {index} image {image!r} has no tag or digest",
            )


def check_links(path: Path, value: object) -> None:
    links = parsed_block(path, "artifacthub.io/links", value)
    if links is None:
        return
    if not isinstance(links, list) or not links:
        error(path, "artifacthub.io/links must be a non-empty YAML list")
        return

    names: set[str] = set()
    for index, entry in enumerate(links, 1):
        if not isinstance(entry, dict):
            error(path, f"artifacthub.io/links entry {index} must be a mapping")
            continue
        name = entry.get("name")
        url = entry.get("url")
        if not isinstance(name, str) or not name.strip():
            error(path, f"artifacthub.io/links entry {index} needs a name")
        else:
            names.add(name.lower())
        if not isinstance(url, str) or not url.strip():
            error(path, f"artifacthub.io/links entry {index} needs a url")
            continue
        parts = urlsplit(url)
        if parts.scheme != "https" or not parts.netloc:
            error(path, f"artifacthub.io/links entry {index} url must be absolute https: {url!r}")

    for required in REQUIRED_LINKS:
        if not any(required in name for name in names):
            error(path, f"artifacthub.io/links is missing a {required} link")


def check_chart(path: Path) -> None:
    chart = load_chart(path)
    if chart is None:
        return

    check_icon(path, chart)

    annotations = chart.get("annotations")
    if not isinstance(annotations, dict):
        error(path, "missing `annotations` mapping")
        return

    for annotation in REQUIRED_ANNOTATIONS:
        if annotation not in annotations:
            error(path, f"missing required annotation {annotation}")

    check_changes(path, annotations.get("artifacthub.io/changes"))
    check_images(path, annotations.get("artifacthub.io/images"))
    check_links(path, annotations.get("artifacthub.io/links"))


def main() -> int:
    for chart in CHARTS:
        check_chart(chart)

    if errors:
        for message in errors:
            print(f"FAIL: {message}", file=sys.stderr)
        print(
            f"check-artifacthub: {len(errors)} metadata error(s); "
            "fix both Chart.yaml files and retry",
            file=sys.stderr,
        )
        return 1

    print(f"check-artifacthub: OK ({len(CHARTS)} charts validated)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
