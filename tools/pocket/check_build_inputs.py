#!/usr/bin/env python3
"""Validate and summarize the P00 build input inventory.

Run from any directory with:
    python3 tools/pocket/check_build_inputs.py [--manifest PATH]

The manifest uses repository-root-relative paths. This checks inventory
consistency; it does not run the full Pocket build or validate tool installs.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "tools/pocket/build_inputs.json"
STATUSES = {"present", "generated", "fetch-at-build", "missing", "decision-needed"}
TOP_KEYS = {"schema", "notes", "entries"}
ENTRY_KEYS = {"name", "consumer", "status", "path", "pin", "license", "next_action"}


class ManifestError(ValueError):
    pass


def fail(message: str) -> None:
    raise ManifestError(message)


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"cannot read manifest {path}: {exc}")
    if not isinstance(data, dict):
        fail("manifest root must be a JSON object")
    missing = TOP_KEYS - data.keys()
    if missing:
        fail("manifest missing required keys: " + ", ".join(sorted(missing)))
    if data["schema"] != 1:
        fail("schema must be integer 1")
    if not isinstance(data["notes"], list) or not all(isinstance(x, str) and x.strip() for x in data["notes"]):
        fail("notes must be a list of non-empty strings")
    if not isinstance(data["entries"], list):
        fail("entries must be a list")

    seen: set[str] = set()
    for index, entry in enumerate(data["entries"]):
        label = f"entries[{index}]"
        if not isinstance(entry, dict):
            fail(f"{label} must be an object")
        absent = ENTRY_KEYS - entry.keys()
        if absent:
            fail(f"{label} missing required keys: " + ", ".join(sorted(absent)))
        for key in ENTRY_KEYS:
            if not isinstance(entry[key], str) or (key != "path" and not entry[key].strip()):
                fail(f"{label}.{key} must be a non-empty string" if key != "path" else f"{label}.path must be a string")
        name = entry["name"]
        if name in seen:
            fail(f"duplicate logical name: {name}")
        seen.add(name)
        if entry["status"] not in STATUSES:
            fail(f"{label}.status has unsupported value {entry['status']!r}")
        rel = entry["path"]
        if rel:
            p = Path(rel)
            if p.is_absolute() or ".." in p.parts:
                fail(f"{label}.path must be repository-relative without '..': {rel}")
            if entry["status"] == "present" and not (ROOT / p).exists():
                fail(f"{label} is marked present but path does not exist: {rel}")
    return data


def cross_check(data: dict[str, Any]) -> None:
    entries = {entry["name"]: entry for entry in data["entries"]}
    makefile = ROOT / "Makefile"
    text = makefile.read_text(encoding="utf-8")
    # SFLP is continued across lines; collect its assignment through SFLS.
    match = re.search(r"(?ms)^SFLP\s*=\s*(.*?)^SFLS\s*=", text)
    if not match:
        fail("could not find SFLP assignment in Makefile")
    make_inputs = match.group(1).replace("\\\n", " ").split()
    for name in make_inputs:
        logical = "make:" + name
        if logical not in entries:
            fail(f"Makefile input absent from manifest: {name}")
        if entries[logical]["path"] != name:
            fail(f"{logical} path must match its Makefile input ({name})")

    # The listed Pocket SFL+ includes are tracked literally because their
    # resolution depends on the original nested project layout.
    core_sfl = (ROOT / "Pocket/core.sflp").read_text(encoding="latin1")
    includes = re.findall(r'^\s*%i\s+"([^"]+)"', core_sfl, flags=re.MULTILINE)
    include_entries = {entry.get("include_string"): entry for entry in data["entries"]
                       if entry.get("include_string")}
    for include in includes:
        if include not in include_entries:
            fail(f"Pocket/core.sflp include absent from manifest: {include}")
        expected_name = Path(include).name
        recorded_name = Path(include_entries[include]["path"]).name
        if recorded_name != expected_name:
            fail(f"manifest path for include {include} must end in {expected_name}")

    # Require the specifically documented external core_top modules to map to
    # inventory rows. Internal modules are covered by the SFLP source list.
    top = (ROOT / "Pocket/core_top.v").read_text(encoding="latin1")
    referenced_modules = {"sdram128_burstn_ctrl_100", "main_pll_0002", "synch_3"}
    module_entries = {entry.get("module") for entry in data["entries"] if entry.get("module")}
    for module in sorted(referenced_modules - module_entries):
        fail(f"Pocket/core_top.v external module absent from manifest: {module}")
    for module in referenced_modules:
        if not re.search(rf"\b{re.escape(module)}\b", top):
            fail(f"manifest module is not referenced by Pocket/core_top.v: {module}")


def summary(data: dict[str, Any]) -> str:
    counts = Counter(entry["status"] for entry in data["entries"])
    lines = [f"Build input manifest: {len(data['entries'])} entries"]
    lines.append("Status counts: " + ", ".join(f"{status}={counts[status]}" for status in sorted(STATUSES) if counts[status]))
    for entry in sorted(data["entries"], key=lambda item: item["name"]):
        path = entry["path"] or "(no file path)"
        lines.append(f"{entry['status']:15} {entry['name']} -> {path}")
    lines.append("Inventory consistency only; no complete Pocket project build is claimed.")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST,
                        help="manifest JSON (default: tools/pocket/build_inputs.json)")
    args = parser.parse_args()
    try:
        data = load_manifest(args.manifest)
        cross_check(data)
    except ManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(summary(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
