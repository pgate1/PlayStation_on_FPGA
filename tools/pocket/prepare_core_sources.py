#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare a patched copy of the upstream SFL+ sources for the PS1 core.

Copies the repository-root *.sflp and *.v files (and demo/) into a new
directory, verifies each patched file's pristine SHA-256, applies the minimal
repairs in Pocket/source_fixes/fixes.json and writes core_sources.json with
the hash of every prepared file. Upstream files are never modified.

--check also translates PlayStation_core with sflc (--hierarchy
--register-banks) and elaborates it with Icarus. That is structural evidence
only: not native-sfl2vl equivalence, synthesis, timing or hardware behaviour.

Usage: prepare_core_sources.py OUT_DIR [--check] [--timeout SECONDS]
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXES = REPO / 'Pocket' / 'source_fixes' / 'fixes.json'
TOP = 'PlayStation_core'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    sys.exit(1)


def apply_fixes(out, spec):
    by_file = {}
    for fix in spec['fixes']:
        by_file.setdefault(fix['file'], []).append(fix)
    applied = []
    for name, fixes in sorted(by_file.items()):
        path = out / name
        raw = path.read_bytes()
        pinned = {f['upstream_sha256'] for f in fixes}
        if len(pinned) != 1 or sha256(raw) not in pinned:
            fail('%s: upstream SHA-256 %s does not match the reviewed %s; re-review %s'
                 % (name, sha256(raw), ', '.join(sorted(pinned)), ', '.join(f['id'] for f in fixes)))
        text = raw.decode('latin-1')
        eol = '\r\n' if '\r\n' in text else '\n'
        for fix in fixes:
            old, new = fix['old'].replace('\n', eol), fix['new'].replace('\n', eol)
            count = text.count(old)
            if count != 1:
                fail('%s %s: expected exactly one match, found %d' % (fix['id'], name, count))
            text = text.replace(old, new)
            applied.append(fix['id'])
        path.write_bytes(text.encode('latin-1'))
    for extra in spec.get('extra_files', []):
        data = (REPO / extra['source']).read_bytes()
        if sha256(data) != extra['sha256']:
            fail('%s: SHA-256 mismatch' % extra['source'])
        if (out / extra['file']).exists():
            fail('%s already exists upstream; re-review the fix set' % extra['file'])
        (out / extra['file']).write_bytes(data)
    return applied


def run(cmd, timeout, **kw):
    print('$ ' + ' '.join(str(c) for c in cmd), flush=True)
    try:
        return subprocess.run([str(c) for c in cmd], timeout=timeout, text=True,
                              capture_output=True, **kw)
    except FileNotFoundError:
        fail('missing tool: ' + str(cmd[0]))
    except subprocess.TimeoutExpired:
        fail('timeout after %ds: %s' % (timeout, cmd[0]))


def check(out, timeout):
    sv = out / (TOP + '.sv')
    result = run([sys.executable, '-I', REPO / 'tools' / 'sflc' / 'sflc.py', '--hierarchy',
                  '--register-banks', TOP + '.sflp'], timeout, cwd=out,
                 env={'PYTHONDONTWRITEBYTECODE': '1', 'LC_ALL': 'C', 'PATH': '/usr/bin:/bin'})
    if result.returncode:
        fail('sflc exit %d: %s' % (result.returncode, result.stderr.strip()[-2000:]))
    sv.write_text(result.stdout)
    print('translated %s: %d bytes' % (sv.name, sv.stat().st_size))
    leaves = sorted(p.name for p in out.glob('*.v'))
    result = run(['iverilog', '-g2012', '-s', TOP, '-t', 'null', sv.name, *leaves], timeout, cwd=out)
    output = (result.stdout + result.stderr).strip()
    if output: print(output[-4000:])
    if result.returncode:
        fail('iverilog elaboration exit %d' % result.returncode)
    print('ELABORATED %s with %d Verilog leaves (structural only; not synthesis or timing)'
          % (TOP, len(leaves)))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('out', type=Path)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    out = args.out.resolve()
    if out.exists() and any(out.iterdir()):
        fail('%s exists and is not empty' % out)
    if REPO in [out, *out.parents] and (REPO / 'Pocket' / 'build') not in [out, *out.parents]:
        fail('output inside the repository must be under Pocket/build/')
    spec = json.loads(FIXES.read_text())
    if spec.get('schema') != 1: fail('unsupported fixes schema')
    out.mkdir(parents=True, exist_ok=True)
    for src in sorted([*REPO.glob('*.sflp'), *REPO.glob('*.v')]):
        shutil.copyfile(src, out / src.name)
    shutil.copytree(REPO / 'demo', out / 'demo')
    applied = apply_fixes(out, spec)
    files = {str(p.relative_to(out)): sha256(p.read_bytes())
             for p in sorted(out.rglob('*')) if p.is_file()}
    (out / 'core_sources.json').write_text(json.dumps({
        'schema': 1, 'fixes_sha256': sha256(FIXES.read_bytes()),
        'applied': applied, 'files': files}, indent=2) + '\n')
    print('PREPARED %d files, fixes %s -> %s' % (len(files), ' '.join(applied), out))
    if args.check:
        check(out, args.timeout)


if __name__ == '__main__':
    main()
