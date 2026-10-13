#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare a complete Pocket PS1 Quartus project (Q-L1-14, milestone 1).

Layout of the new directory (must not exist; must be inside Pocket/build/):
  ap_core.qpf/qsf, apf/, core/   pinned APF template (pins, SDC, bridge)
  core/core_top.v                author's Pocket top (git HEAD), patched copy
  core/main_pll_0002.v           author's missing PLL, regenerated from the
                                 template PLL (50/100/100+90deg/25/25+90deg MHz)
  core/core_constraints.sdc      clock groups for that PLL
  ps1/sfl/                       prepare_core_sources.py --shared-spu output,
                                 plus Pocket/core.sflp (git HEAD), patched copy
  ps1/rtl/                       sflc output (core.sv, reverb.sv), SPU, leaves,
                                 replacement modules, adapter, audio, shims
  ps1_build.json                 hashes of every input and prepared file

Edits come only from Pocket/source_fixes/pocket_top_fixes.json (each pinned to
the source's SHA-256 and matched exactly once). Upstream files, the template
cache and untracked replacement modules are never modified. Quartus is not run.

--check elaborates the translated `core` hierarchy with Icarus (structural
only; interface stubs for Intel primitives are used for that check alone).

Information-only variants (recorded in the manifest; not the Pocket build):
  --device 5CEBA9F23C8   same F23 package, larger die: measures the full
                         requirement when the real device overflows. Quartus
                         25.1 rejects 16 template cram1 locations on this die
                         (A9_ILLEGAL_PINS); only those location assignments are
                         dropped (cram1 is unused and tied in this build);
  --qsf-profile neutral  Quartus default synthesis settings instead of the
                         template's speed-oriented ones (see NEUTRAL_QSF).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/apf'))
import fetch_diagnostic_reference as reference  # noqa: E402

FIXES = ROOT / 'Pocket/source_fixes/pocket_top_fixes.json'
SFLC = ROOT / 'tools/sflc/sflc.py'
OWNED_RTL = ['Pocket/rtl/sdram128_burstn_adapter.sv', 'Pocket/audio/pocket_audio_out.sv']
SPU_SV = ['spu_dsp_shared.sv', 'DigitalSignalProcessor_shared.sv']
# PLL outputs as core_top.v uses them: clk_50, dram_ctrl_clk, dram_clk source
# (sdr_phy clk2x_90), clk_25 (video), clk_25_90deg (video DDR clock).
PLL = [('50.000000 MHz', '0 ps'), ('100.000000 MHz', '0 ps'), ('100.000000 MHz', '2500 ps'),
       ('25.000000 MHz', '0 ps'), ('25.000000 MHz', '10000 ps')]
SDC = '''#
# Q-L1-14 Pocket PS1 top: clock groups for main_pll_0002 (core_top.v instance ic|mpll).
# All PLL outputs are related (one VCO); APF clocks are asynchronous to them.
# The audio FIFO (clk_50 -> clk_74a) relies on these asynchronous groups.
# Not a timing signoff: SDRAM pad timing (sdr_phy) is unconstrained here.
#
set_clock_groups -asynchronous \\
 -group { bridge_spiclk } \\
 -group { clk_74a } \\
 -group { clk_74b } \\
 -group { ic|mpll|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \\
          ic|mpll|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \\
          ic|mpll|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk \\
          ic|mpll|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk \\
          ic|mpll|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk }
'''
# cram1 pin locations Quartus 25.1 reports as illegal (171016) on 5CEBA9F23C8
A9_ILLEGAL_PINS = ['cram1_a[16]', 'cram1_a[17]', 'cram1_a[18]', 'cram1_a[19]', 'cram1_a[20]',
                   'cram1_a[21]', 'cram1_clk', 'cram1_ce0_n', 'cram1_we_n', 'cram1_ub_n', 'cram1_lb_n',
                   'cram1_dq[0]', 'cram1_dq[1]', 'cram1_dq[2]', 'cram1_dq[8]', 'cram1_dq[9]']
# --qsf-profile neutral: template value -> Quartus default (information only)
NEUTRAL_QSF = {'OPTIMIZATION_TECHNIQUE SPEED': 'OPTIMIZATION_TECHNIQUE BALANCED',
               'MUX_RESTRUCTURE OFF': 'MUX_RESTRUCTURE AUTO',
               'SAFE_STATE_MACHINE ON': 'SAFE_STATE_MACHINE OFF',
               'PRE_MAPPING_RESYNTHESIS ON': 'PRE_MAPPING_RESYNTHESIS OFF',
               'ADV_NETLIST_OPT_SYNTH_WYSIWYG_REMAP ON': 'ADV_NETLIST_OPT_SYNTH_WYSIWYG_REMAP OFF',
               'OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"': 'OPTIMIZATION_MODE BALANCED'}
CHECK_STUBS = '''// interface-only stubs for the Icarus structural check (never in the project)
module sld_virtual_jtag #(parameter sld_auto_instance_index = "YES", sld_instance_index = 0,
  sld_ir_width = 1, sld_sim_action = "", sld_sim_n_scan = 0, sld_sim_total_length = 0,
  lpm_type = "sld_virtual_jtag", lpm_hint = "") (
  output tdi, output tck, output [sld_ir_width-1:0] ir_in, input tdo, input [sld_ir_width-1:0] ir_out,
  output virtual_state_cdr, output virtual_state_sdr, output virtual_state_e1dr,
  output virtual_state_pdr, output virtual_state_e2dr, output virtual_state_udr,
  output virtual_state_cir, output virtual_state_uir, output tms, output jtag_state_tlr,
  output jtag_state_rti, output jtag_state_sdrs, output jtag_state_cdr, output jtag_state_sdr,
  output jtag_state_e1dr, output jtag_state_pdr, output jtag_state_e2dr, output jtag_state_udr,
  output jtag_state_sirs, output jtag_state_cir, output jtag_state_sir, output jtag_state_e1ir,
  output jtag_state_pir, output jtag_state_e2ir, output jtag_state_uir);
endmodule
'''


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_head(path: str) -> bytes:
    return subprocess.run(['git', '-C', str(ROOT), 'show', 'HEAD:' + path],
                          check=True, capture_output=True).stdout


def patch(raw: bytes, fixes: list, label: str) -> tuple[bytes, list]:
    pinned = {f['upstream_sha256'] for f in fixes}
    if len(pinned) != 1 or sha256(raw) not in pinned:
        raise ValueError('%s: SHA-256 %s does not match the reviewed %s; re-review %s'
                         % (label, sha256(raw), ', '.join(sorted(pinned)),
                            ', '.join(f['id'] for f in fixes)))
    text = raw.decode('latin-1')
    eol = '\r\n' if '\r\n' in text else '\n'
    for fix in fixes:
        old, new = fix['old'].replace('\n', eol), fix['new'].replace('\n', eol)
        if text.count(old) != 1:
            raise ValueError('%s %s: expected exactly one match, found %d'
                             % (fix['id'], label, text.count(old)))
        text = text.replace(old, new)
    return text.encode('latin-1'), [f['id'] for f in fixes]


def run(cmd, cwd, timeout, stdout=None):
    print('$ ' + ' '.join(str(c) for c in cmd), flush=True)
    env = {'PYTHONDONTWRITEBYTECODE': '1', 'LC_ALL': 'C', 'PATH': os.environ.get('PATH', '/usr/bin:/bin')}
    result = subprocess.run([str(c) for c in cmd], cwd=cwd, timeout=timeout, env=env,
                            stdout=stdout or subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        err = result.stderr.decode('latin-1', 'replace').strip()[-3000:]
        raise ValueError('%s exit %d: %s' % (Path(str(cmd[min(2, len(cmd) - 1)])).name, result.returncode, err))
    return result


def pll_source(template: str) -> str:
    text = template.replace('module  mf_pllbase_0002(', 'module  main_pll_0002(')
    if 'module  main_pll_0002(' not in text:
        raise ValueError('template PLL module header changed')
    for i, (freq, phase) in enumerate(PLL):
        text, n1 = re.subn(r'\.output_clock_frequency%d\("[^"]*"\)' % i,
                           '.output_clock_frequency%d("%s")' % (i, freq), text)
        text, n2 = re.subn(r'\.phase_shift%d\("[^"]*"\)' % i, '.phase_shift%d("%s")' % (i, phase), text)
        if n1 != 1 or n2 != 1:
            raise ValueError('template PLL output %d not found exactly once' % i)
    if '.number_of_clocks(5)' not in text:
        raise ValueError('template PLL is not a 5-output PLL')
    return '// Q-L1-14: generated from the APF template mf_pllbase_0002.v (frequencies/phases only)\n' + text


def edit_qsf(text: str, device: str, profile: str) -> str:
    def swap(text, old, new):
        if text.count('-name ' + old + '\n') != 1:
            raise ValueError('template QSF setting not found exactly once: ' + old)
        return text.replace('-name ' + old + '\n', '-name ' + new + '\n')
    # SignalTap file assignments are dropped below; do not leave SignalTap enabled
    text = swap(text, 'ENABLE_SIGNALTAP ON', 'ENABLE_SIGNALTAP OFF')
    if device != '5CEBA4F23C8':
        text = swap(text, 'DEVICE 5CEBA4F23C8', 'DEVICE ' + device)
        for pin in A9_ILLEGAL_PINS:
            pattern = r'set_location_assignment PIN_\w+ -to %s\n' % re.escape(pin)
            text, count = re.subn(pattern, '', text)
            if count != 1:
                raise ValueError('expected one location assignment for ' + pin)
    if profile == 'neutral':
        for old, new in NEUTRAL_QSF.items():
            text = swap(text, old, new)
    return text


def prepare(destination: Path, reverb_in_spu_ram: bool, options: list, check: bool, timeout: int,
            device: str = '5CEBA4F23C8', profile: str = 'template') -> None:
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
    spec = json.loads(FIXES.read_text())
    if spec.get('schema') != 1:
        raise ValueError('unsupported pocket_top_fixes schema')
    known = {o['option'] for o in spec.get('options', [])}
    if set(options) - known:
        raise ValueError('unknown option(s): ' + ', '.join(sorted(set(options) - known)))
    chosen = [*spec['fixes'], *[o for o in spec.get('options', []) if o['option'] in options]]

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.ps1-stage-', dir=destination.parent) as tmp:
        stage = Path(tmp) / 'project'
        shutil.copytree(cache / 'src/fpga', stage,
                        ignore=shutil.ignore_patterns('output_files', 'db', 'incremental_db'))
        sfl, rtl = stage / 'ps1/sfl', stage / 'ps1/rtl'
        rtl.mkdir(parents=True)
        # 1. PS1 core sources with the shared SPU (lead's tool; not edited here)
        cmd = [sys.executable, '-I', ROOT / 'tools/pocket/prepare_core_sources.py', sfl, '--shared-spu']
        if reverb_in_spu_ram:
            cmd.append('--reverb-in-spu-ram')
        print(run(cmd, ROOT, timeout).stdout.decode().strip().splitlines()[-1])
        core_sources = json.loads((sfl / 'core_sources.json').read_text())

        # 2. upstream Pocket top from git HEAD and board-level view_ram_ctrl, patched copies
        (sfl / 'Pocket').mkdir()
        targets = {'Pocket/core.sflp': (git_head('Pocket/core.sflp'), sfl / 'Pocket/core.sflp'),
                   'Pocket/core_top.v': (git_head('Pocket/core_top.v'), stage / 'core/core_top.v'),
                   'view_ram_ctrl.sflp': ((sfl / 'view_ram_ctrl.sflp').read_bytes(), sfl / 'view_ram_ctrl.sflp')}
        applied, inputs = [], {}
        for name, (raw, out) in targets.items():
            fixes = [f for f in chosen if f['file'] == name]
            data, ids = patch(raw, fixes, name)
            out.write_bytes(data)
            applied += ids
            inputs[name + (' (git HEAD)' if name.startswith('Pocket/') else ' (prepared copy)')] = sha256(raw)
        if set(f['file'] for f in chosen) - set(targets):
            raise ValueError('fixes for unknown files')

        # 3. generated interfaces/shims and pinned untracked inputs
        for gen in spec['generated_files']:
            (stage / 'ps1' / gen['file']).write_text(gen['content'])
        for item in spec['copied_inputs']:
            data = (ROOT / item['source']).read_bytes()
            if sha256(data) != item['sha256']:
                raise ValueError('%s: SHA-256 %s differs from the pinned %s (owner: %s)'
                                 % (item['source'], sha256(data), item['sha256'], item['owner']))
            (stage / 'ps1' / item['dest']).write_bytes(data)
            inputs[item['source'] + ' (untracked)'] = item['sha256']
        for path in OWNED_RTL:
            data = (ROOT / path).read_bytes()
            (rtl / Path(path).name).write_bytes(data)
            inputs[path] = sha256(data)

        # 4. sflc translation (Q-L1-13's compiler; not edited here)
        with (rtl / 'core.sv').open('wb') as out:
            run([sys.executable, '-I', SFLC, '--hierarchy', '--register-banks', 'core.sflp'],
                sfl / 'Pocket', timeout, stdout=out)
        with (rtl / 'reverb.sv').open('wb') as out:
            run([sys.executable, '-I', SFLC, '--hierarchy', 'reverb.sflp'], sfl, timeout, stdout=out)
        print('translated core.sv %d bytes, reverb.sv %d bytes'
              % ((rtl / 'core.sv').stat().st_size, (rtl / 'reverb.sv').stat().st_size))
        for name in SPU_SV:
            shutil.copyfile(sfl / name, rtl / name)
        leaves = sorted(p.name for p in sfl.glob('*.v'))
        for name in leaves:
            shutil.copyfile(sfl / name, rtl / name)

        # 5. PLL, SDC, QSF
        (stage / 'core/main_pll_0002.v').write_text(
            pll_source((stage / 'core/mf_pllbase/mf_pllbase_0002.v').read_text()))
        (stage / 'core/core_constraints.sdc').write_text(SDC)
        qsf = stage / 'ap_core.qsf'
        lines = edit_qsf(qsf.read_text(), device, profile).splitlines(keepends=True)
        kept = [l for l in lines if not re.search(r'\b(USE_SIGNALTAP_FILE|SIGNALTAP_FILE|SLD_FILE)\b', l)]
        if len(lines) - len(kept) != 3:
            raise ValueError('expected three SignalTap assignments in the template QSF')
        sources = sorted(p.relative_to(stage).as_posix() for p in rtl.iterdir())
        with qsf.open('w') as out:
            out.writelines(kept)
            out.write('\n# Q-L1-14 Pocket PS1 project (tools/pocket/prepare_ps1_project.py)\n')
            out.write('# SignalTap assignments of the template removed (template-only nodes).\n')
            out.write('set_global_assignment -name VERILOG_FILE core/main_pll_0002.v\n')
            for a in ('PLL_COMPENSATION_MODE NORMAL', 'PLL_CHANNEL_SPACING "0.0 KHz"',
                      'PLL_AUTO_RESET OFF', 'PLL_BANDWIDTH_PRESET AUTO'):
                out.write('set_instance_assignment -name %s -to "*main_pll_0002*|altera_pll:altera_pll_i*|*"\n' % a)
            for src in sources:
                kind = 'SYSTEMVERILOG_FILE' if src.endswith('.sv') else 'VERILOG_FILE'
                out.write('set_global_assignment -name %s %s\n' % (kind, src))

        if check:
            with tempfile.TemporaryDirectory() as ctmp:
                stub = Path(ctmp) / 'stubs.v'
                stub.write_text(CHECK_STUBS)
                files = [p for p in sources if p.endswith(('.sv', '.v'))]
                run(['iverilog', '-g2012', '-DVERILATOR', '-s', 'core', '-t', 'null', *files, stub],
                    stage, timeout)
            print('ELABORATED core (structural only; not synthesis, timing or behaviour)')

        hashes = {p.relative_to(stage).as_posix(): sha256(p.read_bytes())
                  for p in sorted(stage.rglob('*')) if p.is_file()}
        manifest = {
            'schema': 1, 'purpose': 'Pocket PS1 project, Q-L1-14 milestone 1 (resource measurement)',
            'reference_revision': reference.REVISION, 'device': device, 'project': 'ap_core',
            'variant': {'shared_spu': True, 'reverb_in_spu_ram': reverb_in_spu_ram, 'options': options,
                        'qsf_profile': profile,
                        'information_only': device != '5CEBA4F23C8' or profile != 'template' or bool(options)},
            'fixes_sha256': sha256(FIXES.read_bytes()), 'applied': applied,
            'core_sources_applied': core_sources.get('applied'),
            'tool_sha256': {p: sha256((ROOT / p).read_bytes()) for p in
                            ('tools/sflc/sflc.py', 'tools/sflc/sflp_parse.py',
                             'tools/pocket/prepare_core_sources.py', 'tools/pocket/prepare_ps1_project.py')},
            'input_sha256': inputs, 'project_sha256': hashes,
            'pll_outputs': PLL,
            'validation': {'icarus_elaboration': 'pass' if check else 'not-run', 'quartus_compile': 'not-run',
                           'timing_review': 'pending', 'pocket_hardware': 'not-run'},
        }
        (stage / 'ps1_build.json').write_text(json.dumps(manifest, indent=1) + '\n')
        if destination.exists():
            raise ValueError('output appeared during preparation; left untouched')
        os.rename(stage, destination)
    print('Prepared Pocket PS1 project: ' + str(destination))
    print('Quartus, from that directory: quartus_sh --flow compile ap_core')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reverb-in-spu-ram', action='store_true')
    parser.add_argument('--option', action='append', default=[],
                        help='extra pocket_top_fixes option (e.g. reverb-off; information only)')
    parser.add_argument('--device', default='5CEBA4F23C8', choices=['5CEBA4F23C8', '5CEBA9F23C8'])
    parser.add_argument('--qsf-profile', default='template', choices=['template', 'neutral'])
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--timeout', type=int, default=1800)
    args = parser.parse_args()
    try:
        prepare(args.output, args.reverb_in_spu_ram, args.option, args.check, args.timeout,
                args.device, args.qsf_profile)
    except (ValueError, OSError, subprocess.SubprocessError, reference.FetchError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
