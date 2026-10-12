#!/usr/bin/env python3
"""Compile and run the bounded Pocket diagnostic video and reset regressions."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


CASES = (
    (
        "video",
        "diagnostic_core",
        "tb_diagnostic_core",
        "PASS diagnostic_core: frames=3 checked_pixels=618600 (204800 clocks/frame)",
    ),
    (
        "reset",
        "diagnostic_reset",
        "tb_diagnostic_reset",
        "PASS diagnostic_reset: releases=5 async_assertions=4",
    ),
)
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


def run_case(
    *,
    name: str,
    design_name: str,
    bench_name: str,
    pass_line: str,
    iverilog: str,
    vvp: str,
    timeout: int,
    build_dir: Path,
) -> int:
    source = REPOSITORY_ROOT / f"Pocket/diagnostic/{design_name}.sv"
    bench = REPOSITORY_ROOT / f"Pocket/diagnostic/{bench_name}.sv"
    for path in (source, bench):
        if not path.is_file():
            print(f"ERROR: required {name} diagnostic input is missing: {path}", file=sys.stderr)
            return 2

    executable = build_dir / f"{bench_name}.vvp"
    compile_result = run_command(
        [iverilog, "-g2012", "-Wall", "-s", bench_name, "-o", str(executable), str(source), str(bench)],
        timeout=timeout,
        label=f"{name} compile",
    )
    if compile_result is None:
        return 124
    if compile_result.returncode != 0:
        print(
            f"ERROR: {name} Icarus compile failed with exit code {compile_result.returncode}",
            file=sys.stderr,
        )
        return compile_result.returncode or 1

    simulation = run_command(
        [vvp, str(executable)],
        timeout=timeout,
        label=f"{name} simulation",
    )
    if simulation is None:
        return 124
    if simulation.returncode != 0:
        print(
            f"ERROR: {name} VVP simulation failed with exit code {simulation.returncode}",
            file=sys.stderr,
        )
        return simulation.returncode or 1

    if re.search(rf"(?m)^{re.escape(pass_line)}\r?$", simulation.stdout) is None:
        print(f"ERROR: {name} simulation did not emit the exact PASS marker: {pass_line}", file=sys.stderr)
        return 1
    return 0


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

    tools = {tool: shutil.which(tool) for tool in ("iverilog", "vvp")}
    missing = [tool for tool, path in tools.items() if path is None]
    if missing:
        print(
            "ERROR: required simulation tool(s) not found on PATH: " + ", ".join(missing),
            file=sys.stderr,
        )
        return 2

    with tempfile.TemporaryDirectory(prefix="pocket-diagnostic-") as temp_dir:
        build_dir = Path(temp_dir)
        for case in CASES:
            name, design_name, bench_name, pass_line = case
            result = run_case(
                name=name,
                design_name=design_name,
                bench_name=bench_name,
                pass_line=pass_line,
                iverilog=tools["iverilog"] or "iverilog",
                vvp=tools["vvp"] or "vvp",
                timeout=args.timeout_seconds,
                build_dir=build_dir,
            )
            if result != 0:
                return result

    print("Diagnostic simulations accepted.")
    return 0


SCRIPT_PATH = Path(__file__).resolve()
REPOSITORY_ROOT = SCRIPT_PATH.parents[2]


if __name__ == "__main__":
    raise SystemExit(main())
