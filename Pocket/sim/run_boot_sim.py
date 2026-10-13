#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build and run the BIOS boot simulation (Q-L1-15).

  run_boot_sim.py build BUILD_DIR            prepare sources (--shared-spu) and build with Verilator
  run_boot_sim.py run BUILD_DIR BIOS.bin OUT [--cycles N] [--frames-every K] [--lat L]

The BIOS image is read from the user's own file and converted to a hex file
inside BUILD_DIR (gitignored when under Pocket/build); it is never copied into
the repository. Frames are written to OUT as PPM files.
"""
import argparse
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def sh(cmd, **kw):
    print('$ ' + ' '.join(str(c) for c in cmd), flush=True)
    return subprocess.run([str(c) for c in cmd], **kw)


def build(bdir):
    src = bdir / 'src'
    if not (src / 'PlayStation_core.sv').exists():
        r = sh([sys.executable, '-I', REPO / 'tools' / 'pocket' / 'prepare_core_sources.py', src,
                '--check', '--shared-spu'], env={'PYTHONDONTWRITEBYTECODE': '1', 'PATH': '/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin'})
        if r.returncode: sys.exit('prepare_core_sources failed')
    files = [src / 'PlayStation_core.sv', src / 'reverb.sv', src / 'spu_dsp_shared.sv',
             src / 'DigitalSignalProcessor_shared.sv', *sorted(src.glob('*.v')),
             REPO / 'Pocket' / 'sim' / 'tb_psx_boot.sv']
    r = sh(['verilator', '--binary', '--timing', '-O3', '--x-assign', 'fast', '--x-initial', 'fast',
            '-Wno-fatal', '-Wno-lint', '-Wno-style', '-Wno-WIDTH', '-Wno-MULTIDRIVEN', '-Wno-UNOPTFLAT',
            '--top-module', 'tb_psx_boot', '-j', '8', '--Mdir', bdir / 'obj', *files],
           stdout=open(bdir / 'verilator.log', 'w'), stderr=subprocess.STDOUT)
    if r.returncode: sys.exit('verilator failed, see %s' % (bdir / 'verilator.log'))
    print('BUILT', bdir / 'obj' / 'Vtb_psx_boot')


def run(bdir, bios, out, cycles, frames_every, lat):
    data = bios.read_bytes()
    print('BIOS %s size=%d sha256=%s' % (bios.name, len(data), hashlib.sha256(data).hexdigest()))
    if len(data) != 524288: sys.exit('expected a 512 KiB BIOS image')
    hexf = bdir / 'bios.hex'
    with hexf.open('w') as f:
        for i in range(0, len(data), 2):
            f.write('%04x\n' % (data[i] | data[i + 1] << 8))
    out.mkdir(parents=True, exist_ok=True)
    r = sh([bdir / 'obj' / 'Vtb_psx_boot', '+bios=%s' % hexf, '+outdir=%s' % out,
            '+cycles=%d' % cycles, '+frames_every=%d' % frames_every, '+lat=%d' % lat])
    sys.exit(r.returncode)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build'); b.add_argument('bdir', type=Path)
    r = sub.add_parser('run'); r.add_argument('bdir', type=Path); r.add_argument('bios', type=Path)
    r.add_argument('out', type=Path); r.add_argument('--cycles', type=int, default=200_000_000)
    r.add_argument('--frames-every', type=int, default=30); r.add_argument('--lat', type=int, default=6)
    a = p.parse_args()
    a.bdir = a.bdir.resolve(); a.bdir.mkdir(parents=True, exist_ok=True)
    if a.cmd == 'build': build(a.bdir)
    else: run(a.bdir, a.bios, a.out.resolve(), a.cycles, a.frames_every, a.lat)


if __name__ == '__main__':
    main()
