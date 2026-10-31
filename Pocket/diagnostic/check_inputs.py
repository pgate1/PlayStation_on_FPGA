#!/usr/bin/env python3
"""Read-only preflight for the Pocket diagnostic core inputs.

Run from any directory:  python3 Pocket/diagnostic/check_inputs.py [--inputs PATH]

Reads Pocket/diagnostic/inputs.json, hashes cached APF files, cross-checks the
manifest against tools/apf/fetch_apf.sh, and reports each input with one state.
It never downloads, fetches, writes or alters any file, and never guesses pins,
clocks or timing.

Exit codes:
  0  every required input is ready
  1  invalid manifest: missing/malformed required field, hash mismatch, or drift
     from tools/apf/fetch_apf.sh
  2  manifest is valid but a prerequisite is blocked (missing cache file, QPF/QSF,
     Quartus, timing reference, or a referenced IP definition)
"""
from __future__ import annotations

import argparse
import json
import hashlib
import re
import shutil
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUTS = ROOT / "Pocket/diagnostic/inputs.json"
FETCH_SCRIPT = ROOT / "tools/apf/fetch_apf.sh"
IP_SUFFIXES = {".v", ".sv", ".vh", ".qip", ".qsys", ".ip"}
IP_EXCLUDE = {"build", ".git", "__pycache__"}
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
ROOT_KEYS = ("schema", "device", "apf", "project", "quartus", "timing_reference", "core_ip")

errors: list[str] = []   # invalid manifest, exit 1
blocked: list[str] = []  # prerequisites missing, exit 2
report: list[str] = []


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_manifest() -> dict[str, str]:
    """Parse the FILES block of fetch_apf.sh as {relative path: sha256}."""
    try:
        text = FETCH_SCRIPT.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        errors.append(f"cannot read {FETCH_SCRIPT.relative_to(ROOT)}: {exc}")
        return {}
    block = re.search(r"FILES='\n(.*?)\n'", text, re.S)
    if not block:
        errors.append(f"cannot find FILES block in {FETCH_SCRIPT.relative_to(ROOT)}")
        return {}
    pairs: dict[str, str] = {}
    for line in block.group(1).splitlines():
        if line.strip():
            rel, want = line.split()
            pairs[rel] = want
    return pairs


def require(obj: Any, key: str, where: str) -> Any:
    if not isinstance(obj, dict) or key not in obj:
        message = f"missing required field: {where}.{key}" if where else f"missing required field: {key}"
        if message not in errors:
            errors.append(message)
        return None
    return obj[key]


def is_object(value: Any, name: str) -> bool:
    """True for a JSON object. A missing section is already reported by require()."""
    if isinstance(value, dict):
        return True
    if value is not None:
        errors.append(f"{name} must be an object")
    return False


def check_apf(data: dict[str, Any]) -> None:
    apf = require(data, "apf", "")
    if not is_object(apf, "apf"):
        return
    revision = require(apf, "revision", "apf")
    cache = require(apf, "cache_dir", "apf")
    files = require(apf, "files", "apf")
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        errors.append("apf.revision must be a 40-character commit hash")
    if not isinstance(cache, str):
        errors.append("apf.cache_dir must be a string")
        return
    if not isinstance(files, list) or not files:
        errors.append("apf.files must be a non-empty list")
        return

    pinned = fetch_manifest()
    listed: dict[str, str] = {}
    cache_dir = ROOT / cache
    for entry in files:
        rel = entry.get("path") if isinstance(entry, dict) else None
        want = entry.get("sha256") if isinstance(entry, dict) else None
        if not isinstance(rel, str) or not isinstance(want, str) or not SHA_RE.match(want):
            errors.append(f"malformed apf.files entry: {entry!r}")
            continue
        listed[rel] = want
        path = cache_dir / rel
        if not path.is_file():
            blocked.append(f"apf file missing from cache: {cache}/{rel}")
            report.append(f"apf    {rel}: missing")
            continue
        got = sha256(path)
        if got != want:
            errors.append(f"hash mismatch: {cache}/{rel} expected {want} got {got}")
            report.append(f"apf    {rel}: hash-mismatch")
        else:
            report.append(f"apf    {rel}: ok")

    if pinned and listed != pinned:
        only_manifest = sorted(set(listed) - set(pinned))
        only_script = sorted(set(pinned) - set(listed))
        differ = sorted(k for k in set(listed) & set(pinned) if listed[k] != pinned[k])
        errors.append(
            "apf.files drifted from fetch_apf.sh: "
            f"manifest-only={only_manifest} script-only={only_script} differing={differ}"
        )


def check_project(data: dict[str, Any]) -> None:
    project = require(data, "project", "")
    if not is_object(project, "project"):
        return
    for key in ("qpf", "qsf"):
        value = require(project, key, "project")
        if value is None:
            blocked.append(f"project.{key} not recorded (no authoritative Pocket {key.upper()})")
            report.append(f"project {key}: missing")
        elif not (ROOT / value).is_file():
            blocked.append(f"project.{key} path does not exist: {value}")
            report.append(f"project {key}: missing-file {value}")
        else:
            report.append(f"project {key}: present {value}")


def check_quartus(data: dict[str, Any]) -> None:
    quartus = require(data, "quartus", "")
    if not is_object(quartus, "quartus"):
        return
    exe = require(quartus, "executable", "quartus")
    if not isinstance(exe, str) or not exe:
        errors.append("quartus.executable must be a non-empty string")
        return
    if shutil.which(exe) is None:
        blocked.append(f"Quartus tool not on PATH: {exe}")
        report.append(f"quartus {exe}: missing")
    elif not quartus.get("version"):
        blocked.append(f"Quartus found but quartus.version not recorded: {exe}")
        report.append(f"quartus {exe}: present, version unrecorded")
    else:
        report.append(f"quartus {exe}: present, version {quartus['version']}")


def check_timing(data: dict[str, Any]) -> None:
    timing = require(data, "timing_reference", "")
    if not is_object(timing, "timing_reference"):
        return
    path = require(timing, "path", "timing_reference")
    for key in ("pixel_clock_hz", "h_total", "v_total", "source"):
        require(timing, key, "timing_reference")
    if path is None:
        blocked.append("pixel timing reference not recorded")
        report.append("timing reference: missing")
    elif not (ROOT / path).is_file():
        blocked.append(f"timing reference path does not exist: {path}")
        report.append(f"timing reference: missing-file {path}")
    else:
        report.append(f"timing reference: present {path}")


def module_defined(name: str, dirs: list[Path]) -> Path | None:
    pattern = re.compile(rb"\bmodule\s+" + re.escape(name.encode()) + rb"\b")
    for base in dirs:
        for path in sorted(base.rglob("*")):
            if not path.is_file() or path.suffix not in IP_SUFFIXES:
                continue
            if IP_EXCLUDE & set(path.relative_to(ROOT).parts):
                continue
            if pattern.search(path.read_bytes()):
                return path
    return None


def check_core_ip(data: dict[str, Any]) -> None:
    ip = require(data, "core_ip", "")
    if not is_object(ip, "core_ip"):
        return
    required = require(ip, "diagnostic_requires", "core_ip")
    refs = require(ip, "ps1_references", "core_ip")
    dirs = require(ip, "search_dirs", "core_ip")
    if not isinstance(required, list) or not isinstance(refs, list) or not isinstance(dirs, list):
        errors.append("core_ip lists must be lists")
        return
    search = [ROOT / d for d in dirs]
    for name in required:
        if module_defined(name, search) is None:
            blocked.append(f"diagnostic requires IP not defined: {name}")
            report.append(f"core ip {name}: missing")
        else:
            report.append(f"core ip {name}: defined")
    if not required:
        report.append("core ip diagnostic: none required")
    for name in refs:
        found = module_defined(name, search)
        report.append(f"core ip {name} (PS1 only): {'defined' if found else 'missing'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--inputs", type=Path, default=DEFAULT_INPUTS, help="manifest JSON")
    args = parser.parse_args()
    try:
        data = json.loads(args.inputs.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"ERROR: cannot read manifest {args.inputs}: {exc}", file=sys.stderr)
        return 1
    if not isinstance(data, dict):
        print("ERROR: manifest must be a JSON object", file=sys.stderr)
        return 1
    for key in ROOT_KEYS:
        require(data, key, "")
    if data.get("schema") != 1:
        errors.append("schema must be 1")
    if data.get("device") != "5CEBA4F23C8":
        errors.append("device must be 5CEBA4F23C8")

    check_apf(data)
    check_project(data)
    check_quartus(data)
    check_timing(data)
    check_core_ip(data)

    for line in report:
        print(line)
    for line in sorted(set(blocked)):
        print(f"BLOCKED: {line}")
    for line in errors:
        print(f"ERROR: {line}", file=sys.stderr)
    if errors:
        print(f"FAIL: {len(errors)} invalid input(s)", file=sys.stderr)
        return 1
    if blocked:
        print(f"BLOCKED: {len(set(blocked))} prerequisite(s) not ready")
        return 2
    print("OK: all diagnostic inputs ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
