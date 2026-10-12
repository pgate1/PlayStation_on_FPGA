#!/usr/bin/env python3
"""Prepare a separate Pocket diagnostic Quartus project from verified inputs.

This does not run Quartus or copy the upstream example's prebuilt bitstream.
The output directory must not exist; the pinned reference is never modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/apf'))
import fetch_diagnostic_reference as reference

TARGET_REGS = ('read', 'write', 'getfile', 'openfile', 'id', 'slotoffset',
               'bridgeaddr', 'length')


def overlay_core(source: str, video: str) -> str:
    start, end = '// video generation\n', '//\n// audio i2s silence generator\n'
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('pinned video/audio section boundaries do not match')
    a, b = source.index(start), source.index(end)
    if b <= a:
        raise ValueError('pinned video/audio section order does not match')
    source = source[:a] + video + '\n\n' + source[b:]
    for suffix in TARGET_REGS:
        pattern = r'\breg(\s+(?:\[[^\]\n]+\]\s+)?target_dataslot_' + suffix + r'\s*;)'
        source, count = re.subn(pattern, r'wire\1', source)
        if count != 1:
            raise ValueError('unexpected target declaration: ' + suffix)
    return source


def prepare(destination: Path) -> None:
    build_root = (ROOT / 'Pocket/build').resolve()
    destination = destination.absolute()
    if destination.is_symlink() or destination.exists():
        raise ValueError('output exists; choose a new build directory: ' + str(destination))
    destination = destination.resolve()
    if build_root not in destination.parents:
        raise ValueError('output must be a new directory inside Pocket/build')
    cache = build_root / 'reference' / reference.ROOT_NAME
    if cache == destination or cache in destination.parents:
        raise ValueError('output must not be inside the pinned reference')
    reference.validate_files(cache)
    owned = ROOT / 'Pocket/diagnostic'
    inputs = [owned / n for n in ('diagnostic_core.sv', 'diagnostic_reset.sv', 'apf_video.vh')]
    for source in inputs:
        if not source.is_file():
            raise ValueError('missing diagnostic source: ' + str(source))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.diagnostic-stage-', dir=destination.parent) as tmp:
        stage = Path(tmp) / 'project'
        # Never present the template's old SOF/RBF as a product of this build.
        shutil.copytree(cache / 'src/fpga', stage,
                        ignore=shutil.ignore_patterns('output_files', 'db', 'incremental_db'))
        top = stage / 'core/core_top.v'
        top.write_text(overlay_core(top.read_text(), inputs[2].read_text()))
        for source in inputs[:2]:
            shutil.copyfile(source, stage / 'core' / source.name)
        qsf = stage / 'ap_core.qsf'
        with qsf.open('a') as out:
            out.write('\n# Independent diagnostic overlay\n')
            for source in inputs[:2]:
                out.write('set_global_assignment -name SYSTEMVERILOG_FILE core/' + source.name + '\n')
        hashes = {p.relative_to(stage).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sorted(stage.rglob('*')) if p.is_file()}
        manifest = {
            'schema': 1, 'purpose': 'Pocket diagnostic; not the PS1 core',
            'reference_revision': reference.REVISION,
            'device': '5CEBA4F23C8', 'project': 'ap_core',
            'source_sha256': {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in inputs},
            'project_sha256': hashes,
            'validation': {'quartus_compile': 'not-run', 'timing_review': 'pending',
                           'pocket_hardware': 'not-run'},
            'notes': ['Reference QPF/QSF pin assignments, PLL and SDC are copied intact except added source files.',
                      'Inherited clock-group exceptions still require TimeQuest review.',
                      'Upstream output_files are excluded. No new bitstream exists until Quartus runs.'],
        }
        (stage / 'diagnostic_build.json').write_text(json.dumps(manifest, indent=2) + '\n')
        if destination.exists():
            raise ValueError('output appeared during preparation; left untouched')
        os.rename(stage, destination)
    print('Prepared diagnostic project: ' + str(destination))
    print('Quartus, from that directory: quartus_sh --flow compile ap_core')
    print('Not yet compiled, timing-qualified or tested on Pocket.')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'Pocket/build/diagnostic')
    args = parser.parse_args()
    try:
        prepare(args.output)
    except (ValueError, OSError, reference.FetchError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
