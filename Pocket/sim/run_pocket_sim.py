#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build and run the full-chain Pocket boot simulation (Q-L1-16).

  run_pocket_sim.py build BUILD_DIR            Verilator-build the prepared project in BUILD_DIR
  run_pocket_sim.py run BUILD_DIR BIOS.bin OUT [--slot40 FILE] [--cycles N] [--frames-every K]
                                               [--wr-interval C] [--tout-ps P] [--status-every N]
                                               [--stop-on-runaway N] [--sdram-init 0|1]

BUILD_DIR is a directory made by tools/pocket/prepare_ps1_project.py (under
Pocket/build/, gitignored). The simulation compiles that directory's
core/core_top.v, core/core_bridge_cmd.v, apf/common.v and ps1/rtl/* with the
IP stubs and the bench in Pocket/sim/fullchain/. BIOS and frames stay in
gitignored directories; nothing of them is copied into the repository.
The Verilator binary is BUILD_DIR/sim/Vtb_pocket_boot; its log is sim/verilator.log.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BENCH = REPO / 'Pocket' / 'sim' / 'fullchain'
EXCLUDE = {'ram_320x240x15_dp_2k5.sv', 'ram_320x240x15_dp.sv', 'VirtualJTAG.v', 'vjtag_uart.v'}


def sh(cmd, **kw):
    print('$ ' + ' '.join(str(c) for c in cmd), flush=True)
    return subprocess.run([str(c) for c in cmd], **kw)


def build(bdir, jobs):
    manifest = json.loads((bdir / 'ps1_build.json').read_text())
    pll = manifest['pll_outputs']
    core_mhz = float(pll[0][0].split()[0])
    phase_ps = int(pll[2][1].split()[0])
    period_2x_ps = round(1e6 / float(pll[2][0].split()[0]))
    phase_deg = round(360 * phase_ps / period_2x_ps)
    print('PLL: core %.3f MHz, SDRAM clock phase %d deg (manifest)' % (core_mhz, phase_deg))
    rtl = bdir / 'ps1' / 'rtl'
    files = [bdir / 'core' / 'core_top.v', bdir / 'core' / 'core_bridge_cmd.v', bdir / 'apf' / 'common.v',
             *sorted(p for p in rtl.iterdir() if p.suffix in ('.sv', '.v') and p.name not in EXCLUDE),
             BENCH / 'sim_ip_stubs.sv', BENCH / 'tb_pocket_boot.sv']
    sim = bdir / 'sim'
    sim.mkdir(exist_ok=True)
    r = sh(['verilator', '--binary', '--timing', '-O3', '--x-assign', 'fast', '--x-initial', '0',
            '-Wno-fatal', '-Wno-lint', '-Wno-style', '-Wno-WIDTH', '-Wno-MULTIDRIVEN', '-Wno-UNOPTFLAT',
            '-Wno-PINMISSING', '-Wno-TIMESCALEMOD', '-Wno-CASEINCOMPLETE', '-Wno-LATCH',
            '-DSIM_CORE_PERIOD_NS=%.4f' % (1000.0 / core_mhz), '-DSIM_SDRAM_PHASE=%d' % phase_deg,
            '--top-module', 'tb_pocket_boot', '-j', str(jobs), '--Mdir', sim, *files],
           stdout=open(sim / 'verilator.log', 'w'), stderr=subprocess.STDOUT)
    if r.returncode:
        sys.exit('verilator failed, see %s' % (sim / 'verilator.log'))
    print('BUILT', sim / 'Vtb_pocket_boot')


def run(a):
    data = a.bios.read_bytes()
    print('BIOS %s size=%d sha256=%s' % (a.bios.name, len(data), hashlib.sha256(data).hexdigest()))
    if len(data) != 524288:
        sys.exit('expected a 512 KiB BIOS image')
    a.out.mkdir(parents=True, exist_ok=True)
    args = ['+slot20=%s' % a.bios, '+outdir=%s' % a.out, '+cycles=%d' % a.cycles,
            '+frames_every=%d' % a.frames_every, '+wr_interval=%d' % a.wr_interval, '+tout_ps=%d' % a.tout_ps,
            '+status_every=%d' % a.status_every, '+stop_on_runaway=%d' % a.stop_on_runaway,
            '+sdram_init=%d' % a.sdram_init]
    if a.slot40:
        args.append('+slot40=%s' % a.slot40.resolve())
    r = sh([a.bdir / 'sim' / 'Vtb_pocket_boot', *args])
    sys.exit(r.returncode)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = p.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build'); b.add_argument('bdir', type=Path); b.add_argument('-j', type=int, default=8)
    r = sub.add_parser('run'); r.add_argument('bdir', type=Path); r.add_argument('bios', type=Path)
    r.add_argument('out', type=Path); r.add_argument('--slot40', type=Path)
    r.add_argument('--cycles', type=int, default=200_000_000)
    r.add_argument('--frames-every', type=int, default=30)
    r.add_argument('--wr-interval', type=int, default=12, help='clk_74a cycles per loader word')
    r.add_argument('--tout-ps', type=int, default=7000, help='SDRAM read data delay after its clock edge')
    r.add_argument('--status-every', type=int, default=4_000_000)
    r.add_argument('--stop-on-runaway', type=int, default=2_000_000, help='cycles to run after a runaway PC (0: never stop)')
    r.add_argument('--sdram-init', type=int, default=1, help='0: zero, 1: address pattern')
    a = p.parse_args()
    a.bdir = a.bdir.resolve()
    if not (a.bdir / 'ps1_build.json').exists():
        sys.exit('%s is not a prepared project (no ps1_build.json)' % a.bdir)
    if a.cmd == 'build':
        build(a.bdir, a.j)
    else:
        a.bios = a.bios.resolve(); a.out = a.out.resolve()
        run(a)


if __name__ == '__main__':
    main()
