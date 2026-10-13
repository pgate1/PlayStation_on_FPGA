#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Module-level Quartus area measurement on the shared host ristisana.

Builds a small synthesis project (one top entity, the translated core SV and
the Verilog leaves), uploads it to E:\\psx\\area-<name>, starts quartus_map
(optionally quartus_fit) through the mandatory E:\\fpga-shared\\qrun.ps1 and
fetches the per-entity report back. Follows tools/ristisana/RULES.txt: jobs
only via qrun, our own directories only, never blocking an ssh session.

  qmap.py make  NAME --top ENTITY --sv core.sv --leaf-dir DIR [--extra FILE...] [--fit]
  qmap.py push  NAME
  qmap.py start NAME [--fit]
  qmap.py status NAME
  qmap.py fetch NAME            # copies *.map.rpt / *.fit.rpt locally, prints summary
  qmap.py summary NAME          # re-print summary from the local copy

Local project copies live under --root (default: $SFLC_AREA_ROOT or ./area-q).
"""
import argparse
import base64
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOST = 'guest@ristisana'
REMOTE_ROOT = 'E:\\psx'
QSF_HEAD = '''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY %(top)s
set_global_assignment -name NUM_PARALLEL_PROCESSORS 2
'''


def ps(script, timeout=90):
    enc = base64.b64encode(script.encode('utf-16le')).decode()
    cmd = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', HOST,
           'powershell -NoProfile -NonInteractive -EncodedCommand ' + enc]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout + r.stderr).strip()


def root(a):
    return Path(a.root or os.environ.get('SFLC_AREA_ROOT') or 'area-q')


def make(a):
    d = root(a) / a.name
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    files = []
    sv = Path(a.sv)
    shutil.copy(sv, d / sv.name)
    files.append(('SYSTEMVERILOG_FILE', sv.name))
    for leaf in sorted(Path(a.leaf_dir).glob('*.v')):
        shutil.copy(leaf, d / leaf.name)
        files.append(('VERILOG_FILE', leaf.name))
    for extra in a.extra or []:
        extra = Path(extra)
        shutil.copy(extra, d / extra.name)
        files.append(('SYSTEMVERILOG_FILE' if extra.suffix == '.sv' else 'VERILOG_FILE', extra.name))
    qsf = QSF_HEAD % dict(top=a.top)
    qsf += ''.join('set_global_assignment -name %s %s\n' % f for f in files)
    if a.fit:
        # Virtual pins: measure fit of the logic alone, as the first core-fit
        # experiment did. No real pin constraints exist for this estimate.
        qsf += 'set_instance_assignment -name VIRTUAL_PIN ON -to *\n'
    (d / (a.name + '.qsf')).write_text(qsf)
    (d / (a.name + '.qpf')).write_text('PROJECT_REVISION = "%s"\n' % a.name)
    print('made', d)


def push(a):
    d = root(a) / a.name
    remote = '%s:/E:/psx/area-%s' % (HOST, a.name)
    rc, out = ps('if (Test-Path E:\\psx\\area-%s) { Remove-Item -Recurse -Force E:\\psx\\area-%s }; "ok"' % (a.name, a.name))
    r = subprocess.run(['scp', '-q', '-r', '-o', 'BatchMode=yes', str(d), remote], capture_output=True, text=True)
    print('push', a.name, 'exit', r.returncode, r.stderr.strip())
    return r.returncode


def start(a):
    cmd = 'quartus_map %s' % a.name + (' && quartus_fit %s' % a.name if a.fit else '')
    script = ('& powershell -NoProfile -ExecutionPolicy Bypass -File E:\\fpga-shared\\qrun.ps1 '
              '-Session pocket-psx -WorkDir %s\\area-%s -Command "%s" -MaxWaitMinutes 1'
              % (REMOTE_ROOT, a.name, cmd))
    rc, out = ps(script, timeout=150)
    print(out)
    return 0 if 'STARTED' in out else 1


def status(a):
    script = ('$w = "%s\\area-%s"; $d = Get-ChildItem "$w\\qrun-*.log.done" -ErrorAction SilentlyContinue | Select-Object -Last 1; '
              'if ($d) { "DONE exit=$(Get-Content $d.FullName)" } else { "RUNNING" }; '
              '$l = Get-ChildItem "$w\\qrun-*.log" -ErrorAction SilentlyContinue | Select-Object -Last 1; '
              'if ($l) { Get-Content $l.FullName | Select-Object -Last %d }' % (REMOTE_ROOT, a.name, a.tail))
    rc, out = ps(script)
    print(out)
    return 0 if out.startswith('DONE') else 3


def fetch(a):
    d = root(a) / a.name
    for kind in ('map', 'fit'):
        rpt = '%s.%s.rpt' % (a.name, kind)
        r = subprocess.run(['scp', '-q', '-o', 'BatchMode=yes', '%s:/E:/psx/area-%s/%s' % (HOST, a.name, rpt), str(d / rpt)],
                           capture_output=True, text=True)
        if r.returncode == 0:
            print('fetched', rpt)
    return summary(a)


def entity_table(text):
    rows = []
    m = re.search(r'; Analysis & Synthesis Resource Utilization by Entity.*?\n(\+-.*?)\n\n', text, re.S)
    if not m:
        return rows
    for line in m.group(1).split('\n'):
        cells = [c.strip() for c in line.strip().strip(';').split(';')]
        if cells and cells[0].startswith('|'):
            rows.append(cells)
    return rows


def summary(a):
    d = root(a) / a.name
    rpt = d / ('%s.map.rpt' % a.name)
    if not rpt.exists():
        print('no map report for', a.name)
        return 1
    text = rpt.read_text(errors='replace')
    for key in ('Estimate of Logic utilization (ALMs needed)', 'Combinational ALUT usage for logic',
                'Dedicated logic registers', 'Total block memory bits', 'Total DSP Blocks'):
        m = re.search(r'; %s\s*;\s*([^;]+);' % re.escape(key), text)
        if m:
            print('%-45s %s' % (key, m.group(1).strip()))
    rows = entity_table(text)
    print('%-60s %12s %10s %8s %5s' % ('entity', 'ALUTs(self)', 'regs(self)', 'membits', 'DSP'))
    for cells in rows:
        name = cells[0].strip('|')
        if a.depth and name.count('|') > a.depth:
            continue
        if len(cells) < 5:
            continue
        print('%-60s %12s %10s %8s %5s' % (name[:60], cells[1], cells[2], cells[3], cells[4]))
    fit = d / ('%s.fit.rpt' % a.name)
    if fit.exists():
        ftext = fit.read_text(errors='replace')
        for key in ('Logic utilization \\(in ALMs\\)', 'Total registers', 'Total LABs: partially or completely used',
                    'Total block memory bits', 'Total DSP Blocks'):
            m = re.search(r'; %s\s*;\s*([^;]+);' % key, ftext)
            if m:
                print('FIT %-41s %s' % (key.replace('\\', ''), m.group(1).strip()))
        m = re.search(r'Fitter Status\s*;\s*([^;]+);', ftext)
        if m:
            print('FIT status', m.group(1).strip())
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('cmd', choices=['make', 'push', 'start', 'status', 'fetch', 'summary'])
    p.add_argument('name')
    p.add_argument('--top')
    p.add_argument('--sv')
    p.add_argument('--leaf-dir')
    p.add_argument('--extra', action='append')
    p.add_argument('--fit', action='store_true')
    p.add_argument('--root')
    p.add_argument('--tail', type=int, default=3)
    p.add_argument('--depth', type=int, default=2, help='entity table depth to print')
    a = p.parse_args(argv)
    if not re.fullmatch(r'[A-Za-z0-9_-]+', a.name):
        raise SystemExit('bad name')
    return globals()[a.cmd](a) or 0


if __name__ == '__main__':
    sys.exit(main())
