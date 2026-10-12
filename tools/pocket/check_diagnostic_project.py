#!/usr/bin/env python3
"""Read-only input audit for a prepared Pocket diagnostic project.

Checks diagnostic_build.json against the pinned reference revision, the recorded
project file hashes and the repo's diagnostic sources. The QSF and QPF are parsed
as text only; Tcl is never executed. Nothing is written or downloaded.

A pass means the recorded inputs are intact. It is not a Quartus compile, a timing
pass or a bitstream certification; the stored qualification is only echoed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'tools/apf'))
import fetch_diagnostic_reference as reference  # noqa: E402

DEVICE = '5CEBA4F23C8'
PROJECT = 'ap_core'
TOP = 'apf_top'
MANIFEST = 'diagnostic_build.json'
REQUIRED_FILES = ('ap_core.qpf', 'ap_core.qsf', 'apf/apf_top.v', 'core/core_top.v',
                  'core/diagnostic_core.sv', 'core/diagnostic_reset.sv')
REQUIRED_SV = ('core/diagnostic_core.sv', 'core/diagnostic_reset.sv')
# Source inputs and the project copies that must carry identical bytes.
SOURCE_COPIES = {'Pocket/diagnostic/diagnostic_core.sv': 'core/diagnostic_core.sv',
                 'Pocket/diagnostic/diagnostic_reset.sv': 'core/diagnostic_reset.sv'}
# apf_video.vh is embedded in core/core_top.v, so only its repo hash is recorded.
SOURCE_ONLY = ('Pocket/diagnostic/apf_video.vh',)
HEX64 = re.compile(r'[0-9a-f]{64}')


class AuditError(Exception):
    pass


def no_duplicate_keys(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise AuditError(f'duplicate JSON key {key!r}')
        out[key] = value
    return out


def safe_relpath(value, what: str) -> str:
    if not isinstance(value, str) or not value:
        raise AuditError(f'{what}: path must be a non-empty string')
    if ('\\' in value or '\0' in value or value.startswith('/')
            or re.match(r'^[A-Za-z]:', value)):
        raise AuditError(f'{what}: absolute or non-portable path {value!r}')
    parts = PurePosixPath(value).parts
    if any(p in ('', '.', '..') for p in parts) or value != '/'.join(parts):
        raise AuditError(f'{what}: unsafe path {value!r}')
    return value


def regular_file(base: Path, rel: str, what: str) -> Path:
    """Return base/rel if every component is a real directory or regular file."""
    cur = base
    mode = None
    for part in PurePosixPath(rel).parts:
        cur = cur / part
        try:
            mode = cur.lstat().st_mode
        except (FileNotFoundError, NotADirectoryError):
            raise AuditError(f'{what}: missing {rel}') from None
        if stat.S_ISLNK(mode):
            raise AuditError(f'{what}: symbolic link in {rel}')
    if mode is None or not stat.S_ISREG(mode):
        raise AuditError(f'{what}: not a regular file {rel}')
    return cur


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def check_hash(base: Path, rel: str, expected, what: str) -> None:
    if not isinstance(expected, str) or not HEX64.fullmatch(expected):
        raise AuditError(f'{what}: malformed SHA-256 for {rel}')
    actual = sha256_of(regular_file(base, rel, what))
    if actual != expected:
        raise AuditError(f'{what}: hash drift for {rel}')


def qsf_values(text: str, name: str) -> list[str]:
    pattern = re.compile(r'^\s*set_global_assignment\s+-name\s+' + name + r'\s+(\S+)', re.M)
    return [m.group(1).strip('"') for m in pattern.finditer(text)]


def audit(project: Path, repo: Path, out: list[str]) -> None:
    project = project.absolute()
    if not project.is_dir():
        raise AuditError(f'not a directory: {project}')

    manifest_path = regular_file(project, MANIFEST, 'manifest')
    data = json.loads(manifest_path.read_bytes().decode('utf-8'),
                      object_pairs_hook=no_duplicate_keys)
    if not isinstance(data, dict):
        raise AuditError('manifest must be a JSON object')
    out.append('PASS manifest readable (' + MANIFEST + ')')

    if data.get('schema') != 1:
        raise AuditError(f'unsupported schema {data.get("schema")!r}')
    if data.get('reference_revision') != reference.REVISION:
        raise AuditError('reference_revision is not the pinned ' + reference.REVISION)
    if data.get('device') != DEVICE:
        raise AuditError(f'device is not {DEVICE}')
    if data.get('project') != PROJECT:
        raise AuditError(f'project is not {PROJECT}')
    out.append(f'PASS pinned revision {reference.REVISION[:12]}, device {DEVICE}, project {PROJECT}')

    files = data.get('project_sha256')
    if not isinstance(files, dict) or not files:
        raise AuditError('project_sha256 must be a non-empty object')
    for rel, digest in files.items():
        what = 'project file'
        safe_relpath(rel, what)
        if rel == MANIFEST:
            raise AuditError('manifest must not hash itself')
        check_hash(project, rel, digest, what)
    missing = [rel for rel in REQUIRED_FILES if rel not in files]
    if missing:
        raise AuditError('required inputs not recorded: ' + ', '.join(missing))
    out.append(f'PASS {len(files)} recorded project files match their hashes')

    sources = data.get('source_sha256')
    expected_sources = set(SOURCE_COPIES) | set(SOURCE_ONLY)
    if not isinstance(sources, dict) or set(sources) != expected_sources:
        raise AuditError('source_sha256 must record exactly: ' + ', '.join(sorted(expected_sources)))
    for rel, digest in sources.items():
        check_hash(repo, rel, digest, 'repo source')
    for src, copy in SOURCE_COPIES.items():
        if files[copy] != sources[src]:
            raise AuditError(f'project copy {copy} differs from recorded source {src}')
    out.append(f'PASS {len(sources)} repo diagnostic sources match recorded hashes')

    qpf = regular_file(project, PROJECT + '.qpf', 'QPF').read_bytes().decode('latin-1')
    revisions = re.findall(r'^\s*PROJECT_REVISION\s*=\s*"([^"]+)"', qpf, re.M)
    if revisions != [PROJECT]:
        raise AuditError(f'QPF PROJECT_REVISION is {revisions!r}, expected {PROJECT}')

    qsf = regular_file(project, PROJECT + '.qsf', 'QSF').read_bytes().decode('latin-1')
    if qsf_values(qsf, 'DEVICE') != [DEVICE]:
        raise AuditError(f'QSF DEVICE must be exactly {DEVICE}')
    if qsf_values(qsf, 'TOP_LEVEL_ENTITY') != [TOP]:
        raise AuditError(f'QSF TOP_LEVEL_ENTITY must be exactly {TOP}')
    sv_inputs = {v.split()[0] for v in qsf_values(qsf, 'SYSTEMVERILOG_FILE')}
    for rel in REQUIRED_SV:
        if rel not in sv_inputs:
            raise AuditError(f'QSF does not include {rel}')
    out.append(f'PASS QSF/QPF name {DEVICE}, top {TOP} and both diagnostic SV inputs (text parse only)')

    stored = data.get('validation')
    if not isinstance(stored, dict):
        raise AuditError('validation must be an object')
    summary = ', '.join(f'{k}={v}' for k, v in sorted(stored.items()))
    out.append('STORED (recorded by preparer, not verified here): ' + summary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('project', type=Path, help='prepared project directory')
    parser.add_argument('--repo', type=Path, default=ROOT,
                        help='repository root holding Pocket/diagnostic (default: this checkout)')
    args = parser.parse_args()
    lines: list[str] = []
    try:
        audit(args.project, args.repo.absolute(), lines)
    except (AuditError, OSError, ValueError) as exc:
        for line in lines:
            print(line)
        print('FAIL: ' + str(exc), file=sys.stderr)
        print('INPUTS REJECTED. Nothing was executed or modified.', file=sys.stderr)
        return 1
    for line in lines:
        print(line)
    print('INPUTS VERIFIED. Not a Quartus compile, timing pass or bitstream certification.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
