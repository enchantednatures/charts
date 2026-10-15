#!/usr/bin/env python3
"""check-defaults-parity.py — keep the loader defaults and values.yaml in sync.

Issue #26: every default used to exist twice (values.yaml + inline dicts in the
loader) and the two copies had already drifted. The loader defaults now live in
exactly one place, `templates/loader/_defaults.tpl`, and this script enforces
that the copy documented in `values.yaml` still agrees with them.

What it does
------------
1. Renders the test-chart with `--set __ksvcDumpDefaults=true`, which emits
   `ksvc.loader.defaultsDump`: the raw loader default dicts as YAML. Nothing
   else sets `__ksvcDumpDefaults`, so a normal release never renders it.
2. Flattens the dump and `charts/library/ksvc/values.yaml` to leaf paths and
   compares every mapped section (`svcDefaults` -> `services.api`,
   `flaggerDefaults` -> `services.api.flagger`, `pgDefaults` -> `postgres`,
   `dfDefaults` -> `dragonfly`, `globalDefaults` -> `global`,
   `kyvernoDefaults` -> `kyverno`) over the union of their paths: a path that
   exists on only one side, or that exists on both with different values, is a
   mismatch. Intentional, documented divergences belong in
   `charts/library/ksvc/defaults-parity.allow` (patterns match the exact path
   and any path below it) — keep that list tiny.
3. Renders the test-chart with `--set __ksvcProbe=true` and asserts the probe
   ConfigMap shows raw `.Values` are untouched: the probe includes
   `ksvc.loader.generate` twice on top of the include in the test-chart's
   `common.yaml`, then reads `.Values` directly. Every probed key must be
   absent, proving the loader does not inject defaults into `.Values` and that
   a double include does not re-merge or mutate anything.

`kafkaSourceDefaults` and `bucketDefaults` document entries of the
consumer-keyed `kafka.sources` / `objectBuckets` maps, which are empty in
values.yaml (their per-entry schema lives in the README tables); they are
reported as unmapped, not compared.

Usage:
  hack/check-defaults-parity.py

Exit codes:
  0  loader defaults, values.yaml and the probes all agree
  1  a parity mismatch, a probe failure, or a render/setup error
"""

import fnmatch
import os
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
CHART_DIR = REPO_ROOT / "charts" / "library" / "ksvc"
TEST_CHART = CHART_DIR / "test-chart"
VALUES_FILE = CHART_DIR / "values.yaml"
ALLOWLIST_FILE = CHART_DIR / "defaults-parity.allow"
HELM = os.environ.get("HELM", "helm")

# Dump section -> the values.yaml prefix its defaults are documented under.
SECTION_MAP = {
    "svcDefaults": "services.api",
    "flaggerDefaults": "services.api.flagger",
    "pgDefaults": "postgres",
    "dfDefaults": "dragonfly",
    "globalDefaults": "global",
    "kyvernoDefaults": "kyverno",
}

# Sections documenting entries of a consumer-keyed map that ships empty in
# values.yaml (schema is in the README tables, not the values file).
UNMAPPED_SECTIONS = ["kafkaSourceDefaults", "bucketDefaults"]

# Probe ConfigMap keys and their expected raw values. The probe invocation only
# sets services.api.image.repository, so every other key is absent from the raw
# consumer values — the loader must not inject a default into any of them.
PROBE_KEYS = {
    "services.api.image.tag": "ABSENT",
    "services.api.image.pullPolicy": "ABSENT",
    "services.api.scaling.maxScale": "ABSENT",
    "postgres.instances": "ABSENT",
}

def fail(message):
    print(f"::error::defaults-parity: {message}")
    sys.exit(1)

def run(cmd):
    try:
        return subprocess.run(
            cmd, cwd=REPO_ROOT, capture_output=True, text=True, check=True
        ).stdout
    except FileNotFoundError:
        fail(f"'{cmd[0]}' not found on PATH (set HELM to override).")
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(exc.stdout or "")
        sys.stderr.write(exc.stderr or "")
        fail(f"command failed: {chr(32).join(cmd)}")

def render(extra_sets):
    """helm template the test-chart and return the parsed YAML documents."""
    cmd = [HELM, "template", "ksvc-parity", str(TEST_CHART)]
    for item in extra_sets:
        cmd += ["--set", item]
    out = run(cmd)
    return [doc for doc in yaml.safe_load_all(out) if doc]

def flatten(data, prefix=""):
    """Flatten a nested structure to {dotted.path: leaf value}.

    Dicts recurse; scalars, lists, and empty dicts are leaves. Values are
    compared in full (a list is one leaf), which is what the parity contract
    wants: the documented default of `sharedPreloadLibraries` is the list.
    """
    if isinstance(data, dict) and data:
        out = {}
        for key, value in data.items():
            child = f"{prefix}.{key}" if prefix else str(key)
            out.update(flatten(value, child))
        return out
    return {prefix: data}

def under(path, prefix):
    return path == prefix or path.startswith(prefix + ".")

def load_allowlist():
    patterns = []
    if ALLOWLIST_FILE.exists():
        for raw in ALLOWLIST_FILE.read_text().splitlines():
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            patterns.append(line)
    return patterns

def allowlisted(path, patterns):
    return any(path == pat or path.startswith(pat + ".") for pat in patterns)

def main():
    # 1. Build the test-chart dependency from the current library source so the
    #    render below cannot pick up a stale packaged copy.
    tgz = list((TEST_CHART / "charts").glob("*.tgz")) if (TEST_CHART / "charts").exists() else []
    for stale in tgz:
        stale.unlink()
    run([HELM, "dependency", "build", str(TEST_CHART)])

    # 2. Defaults dump -> flattened paths.
    dump_docs = render(["__ksvcDumpDefaults=true", "services.api.image.repository=x/y"])
    dump = None
    for doc in dump_docs:
        if isinstance(doc, dict) and "__ksvcDefaultsDump" in doc:
            dump = doc["__ksvcDefaultsDump"]
            break
    if not isinstance(dump, dict):
        fail("dump render did not emit __ksvcDefaultsDump "
             "(is ksvc.loader.defaultsDump wired into the test-chart?)")

    expected_sections = set(SECTION_MAP) | set(UNMAPPED_SECTIONS)
    missing = expected_sections - set(dump)
    if missing:
        fail(f"dump is missing section(s): {', '.join(sorted(missing))}")

    values = yaml.safe_load(VALUES_FILE.read_text())
    values_paths = flatten(values)

    allow = load_allowlist()
    mismatches = []

    for section, prefix in SECTION_MAP.items():
        dump_paths = flatten(dump[section], prefix)
        # Nested mappings (e.g. flaggerDefaults -> services.api.flagger) own
        # their own subtree; exclude it from the enclosing mapping.
        nested = [p for p in SECTION_MAP.values() if p != prefix and p.startswith(prefix + ".")]
        value_paths = {
            path: value
            for path, value in values_paths.items()
            if under(path, prefix) and not any(under(path, n) for n in nested)
        }
        for path in sorted(set(dump_paths) | set(value_paths)):
            if allowlisted(path, allow):
                continue
            if path not in dump_paths:
                mismatches.append(f"{path}: documented in values.yaml but not defaulted by the loader")
            elif path not in value_paths:
                mismatches.append(f"{path}: loader default is not documented in values.yaml")
            elif dump_paths[path] != value_paths[path]:
                mismatches.append(
                    f"{path}: values.yaml={value_paths[path]!r} loader={dump_paths[path]!r}"
                )

    for section in UNMAPPED_SECTIONS:
        print(f"note: {section} documents entries of a map that is empty in values.yaml "
              "(per-entry schema in README) — not compared")

    # 3. No-mutation / double-include probe.
    probe_docs = render(["__ksvcProbe=true", "services.api.image.repository=x/y"])
    probe = None
    for doc in probe_docs:
        if (isinstance(doc, dict) and doc.get("kind") == "ConfigMap"
                and doc.get("metadata", {}).get("name") == "ksvc-values-probe"):
            probe = doc
            break
    if probe is None:
        fail("probe render did not emit the ksvc-values-probe ConfigMap "
             "(is templates/values-probe.yaml present?)")
    for key, expected in PROBE_KEYS.items():
        actual = str(probe.get("data", {}).get(key, ""))
        if actual != expected:
            mismatches.append(
                f"probe {key}: raw .Values is {actual!r} (expected {expected!r}) — "
                "the loader mutated consumer .Values (double include re-merge?)"
            )
    print("probe OK: ksvc.loader.generate ran 3x in one render and raw .Values stayed untouched")

    if mismatches:
        print("\ndefaults parity FAILED:")
        for mismatch in mismatches:
            print(f"  - {mismatch}")
        print(f"\nAllowlist intentional divergences in {ALLOWLIST_FILE.relative_to(REPO_ROOT)} "
              f"(currently {len(allow)} pattern(s)).")
        sys.exit(1)

    print(f"defaults parity OK: {len(SECTION_MAP)} mapped section(s) agree with values.yaml "
          f"({len(allow)} allowlisted divergence pattern(s))")

if __name__ == "__main__":
    main()
