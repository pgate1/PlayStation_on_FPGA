#!/usr/bin/env python3
"""Structurally elaborate the prepared diagnostic wrapper with Verilator.

This is a structural check only. Interface-only vendor stubs are supplied for
the PLL and data table; their behavior, Quartus synthesis, timing, and hardware
operation are not tested. Verilator warnings are always printed and are never
described as clean lint.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
AUDITOR = ROOT / 'tools/pocket/check_diagnostic_project.py'
STUBS = ROOT / 'tools/pocket/tests/diagnostic_vendor_stubs.sv'
TIMEOUT_SECONDS = 60


class RunError(Exception):
    pass


def run(label: str, command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    print(f'[{label}] command: {shlex.join(command)}')
    try:
        result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=TIMEOUT_SECONDS,
                                check=False)
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ''
        if isinstance(output, bytes):
            output = output.decode(errors='replace')
        print(output, end='' if output.endswith('\n') or not output else '\n')
        print(f'[{label}] timed out after {TIMEOUT_SECONDS}s; exit code: timeout')
        raise RunError(f'{label} timed out') from None
    print(result.stdout, end='' if result.stdout.endswith('\n') or not result.stdout else '\n')
    print(f'[{label}] exit code: {result.returncode}')
    if result.returncode:
        raise RunError(f'{label} failed with exit code {result.returncode}')
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path, help='prepared diagnostic Quartus project directory')
    args = parser.parse_args()

    verilator = shutil.which('verilator')
    if not verilator:
        print('ERROR: required tool not found: verilator', file=sys.stderr)
        return 2
    project = args.project.resolve()
    try:
        version = run('Verilator version', [verilator, '--version'])
        # Reuse the canonical read-only manifest/QSF audit before elaboration.
        run('Prepared-project input audit',
            [sys.executable, str(AUDITOR), str(project)], cwd=ROOT)

        sources = [project / rel for rel in (
            'core/core_top.v', 'core/core_bridge_cmd.v', 'apf/common.v',
            'core/diagnostic_core.sv', 'core/diagnostic_reset.sv')]
        missing = [str(path) for path in sources if not path.is_file()]
        if missing:
            raise RunError('required prepared source missing: ' + ', '.join(missing))
        if not STUBS.is_file():
            raise RunError(f'required simulation-only stubs missing: {STUBS}')

        with tempfile.TemporaryDirectory(prefix='pocket-diagnostic-lint-') as tmp:
            build = Path(tmp)
            command = [verilator, '--lint-only', '--top-module', 'core_top', '-Wno-fatal',
                       '--Mdir', str(build / 'obj_dir'), str(STUBS),
                       *(str(path) for path in sources)]
            result = run('Structural elaboration', command, cwd=project)
        if '%Warning' in result.stdout:
            print('STRUCTURAL ELABORATION PASSED WITH WARNINGS; this is not clean lint.')
        else:
            print('STRUCTURAL ELABORATION PASSED; this is not a behavioral or timing qualification.')
        print('PLL/bridge behavior, synthesis, timing and Pocket hardware remain untested.')
        return 0
    except RunError as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        print('PLL/bridge behavior, synthesis, timing and Pocket hardware remain untested.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
