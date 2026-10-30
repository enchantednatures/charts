#!/usr/bin/env python3
"""Check that relative links in repository Markdown files resolve.

External URLs are checked separately (weekly) because they are network- and
rate-limit-dependent. This check is deterministic and catches the common
failure: a relative path that moved or never existed.

Run:
    python3 hack/check-markdown-links.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", ".omo", ".debug", "node_modules"}
EXTERNAL_SCHEMES = ("http://", "https://", "mailto:", "tel:", "ftp://", "ssh://")
INLINE_LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
REFERENCE_LINK = re.compile(r"^\[[^\]]+\]:\s+(\S+)")

errors: list[str] = []


def markdown_files() -> list[Path]:
    files = []
    for path in ROOT.rglob("*.md"):
        if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
            continue
        files.append(path)
    return sorted(files)


def links(path: Path) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    fence: str | None = None
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.lstrip()
        if fence is not None:
            if stripped.startswith(fence):
                fence = None
            continue
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fence = stripped[:3]
            continue

        line = re.sub(r"`[^`]*`", "", line)
        for match in INLINE_LINK.finditer(line):
            found.append((number, match.group(1).strip()))
        reference = REFERENCE_LINK.match(line)
        if reference:
            found.append((number, reference.group(1).strip()))
    return found


def is_external(target: str) -> bool:
    return target.startswith(EXTERNAL_SCHEMES)


def check_target(source: Path, line: int, target: str) -> None:
    if is_external(target) or target.startswith("#") or not target:
        return

    path_part = unquote(re.split(r"[#?]", target, maxsplit=1)[0])
    if not path_part:
        return

    resolved = (ROOT / path_part.lstrip("/")) if path_part.startswith("/") else (source.parent / path_part)
    if not resolved.exists():
        errors.append(f"{source.relative_to(ROOT)}:{line}: missing local link target {target!r}")


def main() -> int:
    files = markdown_files()
    if not files:
        print("check-markdown-links: no Markdown files found", file=sys.stderr)
        return 1

    total = 0
    for path in files:
        for line, target in links(path):
            total += 1
            check_target(path, line, target)

    if errors:
        for message in errors:
            print(f"FAIL: {message}", file=sys.stderr)
        print(f"check-markdown-links: {len(errors)} broken link(s)", file=sys.stderr)
        return 1

    print(f"check-markdown-links: OK ({total} links in {len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
