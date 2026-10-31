#!/usr/bin/env python3
"""Validate the P00 probe matrix against the SFL probes on disk.

Run from any directory with:
    python3 tools/pocket/check_p00_probes.py [--matrix PATH]

Exit 0 when every probe in tools/sflc/probe/ has a complete row. Exit 1 for an
omitted probe, an unknown probe, or a missing evidence field. This checks the
recorded matrix only; it does not rerun the compiler or Icarus.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PROBE_DIR = ROOT / "tools/sflc/probe"
DEFAULT_MATRIX = ROOT / "tools/pocket/p00_probe_matrix.json"
CAPABILITIES = {"supported", "unsupported-explicit", "local-only"}
ORACLE_STATUSES = {"not-run", "match", "mismatch"}
ROW_KEYS = {"probe", "source", "preprocessing", "compiler_path", "capability",
            "compile", "elaborate", "oracle"}
RESULT_KEYS = {"command", "exit_status", "first_diagnostic", "pass_evidence"}


def probe_names() -> set[str]:
    return {path.stem for path in PROBE_DIR.glob("*.sfl")}


def check_result(label: str, result: Any, expected_prefix: str, errors: list[str]) -> None:
    if not isinstance(result, dict):
        errors.append(f"{label} must be an object")
        return
    missing = RESULT_KEYS - result.keys()
    if missing:
        errors.append(f"{label} missing fields: " + ", ".join(sorted(missing)))
        return
    command = result["command"]
    if not isinstance(command, str) or not command.startswith(expected_prefix):
        errors.append(f"{label}.command must start with {expected_prefix!r}")
    status = result["exit_status"]
    if not isinstance(status, int) or isinstance(status, bool):
        errors.append(f"{label}.exit_status must be an integer")
        return
    diagnostic = result["first_diagnostic"]
    evidence = result["pass_evidence"]
    if not isinstance(diagnostic, str) or not isinstance(evidence, str):
        errors.append(f"{label} diagnostic and evidence must be strings")
        return
    if status == 0 and not evidence.strip():
        errors.append(f"{label} exit 0 needs pass_evidence")
    if status != 0 and not diagnostic.strip():
        errors.append(f"{label} exit {status} needs first_diagnostic")


def check_row(index: int, row: Any, names: set[str], seen: set[str], errors: list[str]) -> None:
    label = f"rows[{index}]"
    if not isinstance(row, dict):
        errors.append(f"{label} must be an object")
        return
    missing = ROW_KEYS - row.keys()
    if missing:
        errors.append(f"{label} missing fields: " + ", ".join(sorted(missing)))
        return
    probe = row["probe"]
    label = f"rows[{index}] ({probe})"
    if probe in seen:
        errors.append(f"{label} duplicate row")
    seen.add(probe)
    if probe not in names:
        errors.append(f"{label} is not a probe in tools/sflc/probe/")
        return

    source = f"tools/sflc/probe/{probe}.sfl"
    if row["source"] != source:
        errors.append(f"{label}.source must be {source}")
    for key in ("preprocessing", "compiler_path", "capability"):
        if not isinstance(row[key], str) or not row[key].strip():
            errors.append(f"{label}.{key} must be a non-empty string")
    if row["capability"] not in CAPABILITIES:
        errors.append(f"{label}.capability must be one of {sorted(CAPABILITIES)}")

    check_result(f"{label}.compile", row["compile"],
                 f"python3 tools/sflc/sflc.py {source}", errors)
    compile_status = row["compile"].get("exit_status") if isinstance(row["compile"], dict) else None

    elaborate = row["elaborate"]
    if elaborate is None:
        if compile_status == 0:
            errors.append(f"{label}.elaborate is null but the compile succeeded")
    else:
        check_result(f"{label}.elaborate", elaborate, "iverilog -g2012 -t null", errors)
        if probe not in elaborate.get("command", ""):
            errors.append(f"{label}.elaborate.command must name the probe")

    oracle = row["oracle"]
    if not isinstance(oracle, dict) or oracle.get("status") not in ORACLE_STATUSES:
        errors.append(f"{label}.oracle.status must be one of {sorted(ORACLE_STATUSES)}")
    elif oracle["status"] == "not-run" and not str(oracle.get("prerequisite", "")).strip():
        errors.append(f"{label}.oracle not-run needs a prerequisite")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX,
                        help="probe matrix JSON (default: tools/pocket/p00_probe_matrix.json)")
    args = parser.parse_args()
    errors: list[str] = []
    try:
        data = json.loads(args.matrix.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"ERROR: cannot read matrix {args.matrix}: {exc}", file=sys.stderr)
        return 1
    if not isinstance(data, dict) or data.get("schema") != 1 or not isinstance(data.get("rows"), list):
        print("ERROR: matrix must be an object with schema 1 and a rows list", file=sys.stderr)
        return 1

    names = probe_names()
    seen: set[str] = set()
    for index, row in enumerate(data["rows"]):
        check_row(index, row, names, seen, errors)
    for probe in sorted(names - seen):
        errors.append(f"probe omitted from matrix: {probe}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"FAIL: {len(errors)} problem(s)", file=sys.stderr)
        return 1
    print(f"OK: {len(seen)} probes recorded, each with command, exit status and evidence")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
