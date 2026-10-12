#!/usr/bin/env python3
"""Compile and run the bounded Pocket diagnostic pixel-domain regression."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


PASS_LINE = "PASS diagnostic_core: frames=3 checked_pixels=618600 (204800 clocks/frame)"
DEFAULT_TIMEOUT_SECONDS = 60


def run_command(command: list[str], *, timeout: int, label: str) -> subprocess.CompletedProcess[str] | None:
    print(f"[{label}] {' '.join(command)}", flush=True)
    try:
        result = subprocess.run(
            command,
            cwd=REPOSITORY_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        print(f"ERROR: {label} timed out after {timeout} seconds", file=sys.stderr)
        if exc.stdout:
            print(_as_text(exc.stdout), file=sys.stderr, end="")
        if exc.stderr:
            print(_as_text(exc.stderr), file=sys.stderr, end="")
        return None

    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    return result


def _as_text(value: str | bytes) -> str:
    return value.decode(errors="replace") if isinstance(value, bytes) else value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"per-command timeout (default: {DEFAULT_TIMEOUT_SECONDS})",
    )
    args = parser.parse_args()
    if args.timeout_seconds < 1:
        parser.error("--timeout-seconds must be at least 1")

    missing = [tool for tool in ("iverilog", "vvp") if shutil.which(tool) is None]
    if missing:
        print(
            "ERROR: required simulation tool(s) not found on PATH: " + ", ".join(missing),
            file=sys.stderr,
        )
        return 2

    source = REPOSITORY_ROOT / "Pocket/diagnostic/diagnostic_core.sv"
    bench = REPOSITORY_ROOT / "Pocket/diagnostic/tb_diagnostic_core.sv"
    for path in (source, bench):
        if not path.is_file():
            print(f"ERROR: required diagnostic input is missing: {path}", file=sys.stderr)
            return 2

    with tempfile.TemporaryDirectory(prefix="pocket-diagnostic-") as build_dir:
        executable = Path(build_dir) / "tb_diagnostic_core.vvp"
        compile_result = run_command(
            [
                shutil.which("iverilog") or "iverilog",
                "-g2012",
                "-Wall",
                "-s",
                "tb_diagnostic_core",
                "-o",
                str(executable),
                str(source),
                str(bench),
            ],
            timeout=args.timeout_seconds,
            label="compile",
        )
        if compile_result is None:
            return 124
        if compile_result.returncode != 0:
            print(f"ERROR: Icarus compile failed with exit code {compile_result.returncode}", file=sys.stderr)
            return compile_result.returncode or 1

        simulation = run_command(
            [shutil.which("vvp") or "vvp", str(executable)],
            timeout=args.timeout_seconds,
            label="simulation",
        )
        if simulation is None:
            return 124
        if simulation.returncode != 0:
            print(f"ERROR: VVP simulation failed with exit code {simulation.returncode}", file=sys.stderr)
            return simulation.returncode or 1

        if re.search(rf"(?m)^{re.escape(PASS_LINE)}\r?$", simulation.stdout) is None:
            print(f"ERROR: simulation did not emit the exact PASS marker: {PASS_LINE}", file=sys.stderr)
            return 1

    print("Diagnostic simulation accepted.")
    return 0


SCRIPT_PATH = Path(__file__).resolve()
REPOSITORY_ROOT = SCRIPT_PATH.parents[2]


if __name__ == "__main__":
    raise SystemExit(main())
