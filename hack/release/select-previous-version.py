#!/usr/bin/env python3
"""Select the highest published SemVer tag lower than ``--current``.

Reads the registry tag list as JSON on stdin (``{"tags": ["1.0.0", ...]}`` or
a bare JSON array) and prints the previous version, or nothing when the chart
has no lower published release. Registry signature tags such as
``sha256-<digest>.sig`` are ignored because they are not SemVer versions.

Discovery failures are not swallowed: invalid JSON, an invalid current version,
or a tag list without a ``tags`` field exits non-zero so the caller can tell a
broken registry response apart from a genuinely first-ever release.
"""

from __future__ import annotations

import argparse
import json
import re
import sys

# Semantic Versioning 2.0.0. Build metadata does not participate in ordering.
_SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


def parse(version: str) -> tuple[int, int, int, tuple[tuple[int, object], ...]] | None:
    """Return a sortable SemVer key, or None when ``version`` is not SemVer."""
    match = _SEMVER.match(version)
    if not match:
        return None

    major, minor, patch = (int(match.group(index)) for index in (1, 2, 3))
    prerelease = match.group(4)
    if prerelease is None:
        # A release sorts above every prerelease of the same core version.
        return (major, minor, patch, ((2, ""),))

    identifiers: list[tuple[int, object]] = []
    for identifier in prerelease.split("."):
        if identifier.isdigit():
            identifiers.append((0, int(identifier)))
        else:
            identifiers.append((1, identifier))
    return (major, minor, patch, tuple(identifiers))


def fail(message: str) -> None:
    print(f"select-previous-version: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", required=True, help="version being released")
    args = parser.parse_args()

    current_key = parse(args.current)
    if current_key is None:
        fail(f"'{args.current}' is not a SemVer version")

    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        fail(f"registry tag list is not valid JSON: {exc}")

    if isinstance(payload, dict):
        tags = payload.get("tags")
        if tags is None:
            fail("registry tag list has no 'tags' field")
    elif isinstance(payload, list):
        tags = payload
    else:
        fail("registry tag list must be a JSON object or array")

    candidates: list[tuple[tuple[int, int, int, tuple[tuple[int, object], ...]], str]] = []
    for tag in tags:
        if not isinstance(tag, str):
            continue
        key = parse(tag)
        if key is not None and key < current_key:
            candidates.append((key, tag))

    if not candidates:
        print(
            f"select-previous-version: no published version lower than {args.current}",
            file=sys.stderr,
        )
        return 0

    candidates.sort()
    print(candidates[-1][1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
