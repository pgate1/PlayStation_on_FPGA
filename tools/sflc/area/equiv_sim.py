#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Cycle-by-cycle output comparison of two sflc translations of one module.

Both inputs are plain SystemVerilog produced by different compiler revisions
(for example `git show HEAD:tools/sflc/sflc.py` versus the working tree). The
same generated random stimulus drives both; every output is written per cycle
and the two traces must be byte-identical. Unknown bits (x) must also match, so
a lowering change that merely alters when a register leaves x is reported.

Usage:
  equiv_sim.py --module NAME --old old.sv --new new.sv [--leaf a.v ...]
               [--cycles N] [--seed S] [--work DIR]

Exit status 0 only when every cycle matches and both simulations print DONE.
This is random-stimulus evidence on externally visible outputs, not a proof.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PORT = re.compile(r'^\s*(input|output)\s+(?:wire\s+|reg\s+)?(?:\[(\d+):0\]\s+)?([A-Za-z_][A-Za-z0-9_$]*)\s*;')


def ports_of(sv_text, module):
    """Return [(direction, name, width)] from an sflc-emitted module header."""
    lines = sv_text.split('\n')
    start = None
    for i, line in enumerate(lines):
        if re.match(r'^module\s+%s\s*\(' % re.escape(module), line):
            start = i
            break
    if start is None:
        raise SystemExit('module %s not found' % module)
    ports = []
    for line in lines[start + 1:]:
        m = PORT.match(line)
        if m:
            d, w, n = m.group(1), m.group(2), m.group(3)
            ports.append((d, n, int(w) + 1 if w else 1))
            continue
        if line.strip().startswith(('input p_reset', 'input wire p_reset')):
            continue
        if line.startswith('endmodule') or not line.startswith('  '):
            break
        if re.match(r'^\s*(wire|reg)\b', line):
            break
    return ports


def bench(module, ports, cycles, seed, trace, probes=()):
    inputs = [(n, w) for d, n, w in ports if d == 'input' and n not in ('p_reset', 'm_clock')]
    outputs = [(n, w) for d, n, w in ports if d == 'output']
    L = ['`timescale 1ns/1ps', 'module tb;', '  reg p_reset = 1, m_clock = 0;']
    for n, w in inputs:
        L.append('  reg [%d:0] %s = 0;' % (w - 1, n))
    for n, w in outputs:
        L.append('  wire [%d:0] %s;' % (w - 1, n))
    conns = ['.p_reset(p_reset)', '.m_clock(m_clock)'] + ['.%s(%s)' % (n, n) for n, _ in inputs + outputs]
    L.append('  %s dut (%s);' % (module, ', '.join(conns)))
    L.append('  integer f, cyc, k, seed; reg [31:0] r;')
    L.append('  task drive; begin')
    for n, w in inputs:
        # One-bit inputs (controls) are sparse so stages and instructions
        # get a chance to run; wide inputs are fully random.
        if w == 1:
            L.append("    r = $urandom; %s = (r[3:0] == 0);" % n)
        else:
            chunks = (w + 31) // 32
            L.append('    for (k = 0; k < %d; k = k + 1) begin r = $urandom; %s = {%s, r}; end'
                     % (chunks, n, n) if chunks > 1 else '    r = $urandom; %s = r;' % n)
    L.append('  end endtask')
    fmt = ' '.join('%h' for _ in outputs)
    names = ', '.join(n for n, _ in outputs)
    L += ['  initial begin',
          '    f = $fopen("%s", "w");' % trace,
          '    seed = %d; r = $urandom(seed);' % seed,
          '    for (cyc = 0; cyc < %d; cyc = cyc + 1) begin' % cycles,
          '      #5 m_clock = 0;',
          '      drive;',
          '      r = $urandom;',
          '      p_reset = (cyc < 2) || (r[9:0] == 0);',
          '      #4;',
          '      $fwrite(f, "%%0d %s", cyc, %s);' % (fmt, names)]
    for name, depth in probes:
        # Internal state probes (memories/registers) strengthen the comparison
        # beyond the port list; a depth of 0 means a scalar signal.
        if depth:
            L.append('      for (k = 0; k < %d; k = k + 1) $fwrite(f, " %%h", dut.%s[k]);' % (depth, name))
        else:
            L.append('      $fwrite(f, " %%h", dut.%s);' % name)
    L += ['      $fwrite(f, "\\n");',
          '      #1 m_clock = 1;',
          '    end',
          '    $fclose(f);',
          '    $display("DONE");',
          '    $finish;',
          '  end',
          'endmodule', '']
    return '\n'.join(L)


def simulate(label, sv, leaves, module, ports, cycles, seed, work, timeout, probes=()):
    trace = work / ('%s.trace' % label)
    tb = work / ('tb_%s.sv' % label)
    tb.write_text(bench(module, ports, cycles, seed, str(trace).replace('\\', '/'), probes))
    vvp = work / ('%s.vvp' % label)
    cmd = ['iverilog', '-g2012', '-s', 'tb', '-o', str(vvp), str(tb), str(sv), *map(str, leaves)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-4000:])
        raise SystemExit('iverilog failed for %s' % label)
    r = subprocess.run(['vvp', '-n', str(vvp)], capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0 or 'DONE' not in r.stdout:
        sys.stderr.write(r.stdout[-4000:] + r.stderr[-4000:])
        raise SystemExit('simulation failed for %s' % label)
    return trace.read_text().split('\n')


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--module', required=True)
    p.add_argument('--old', required=True, type=Path)
    p.add_argument('--new', required=True, type=Path)
    p.add_argument('--leaf', action='append', default=[], type=Path)
    p.add_argument('--leaf-dir', type=Path, help='add every *.v file in this directory as a leaf')
    p.add_argument('--cycles', type=int, default=20000)
    p.add_argument('--seed', type=int, default=1)
    p.add_argument('--work', type=Path)
    p.add_argument('--timeout', type=int, default=1800)
    p.add_argument('--probe', action='append', default=[],
                   help='internal signal to trace as dut.NAME, or NAME=DEPTH for a memory array')
    a = p.parse_args(argv)
    probes = []
    for item in a.probe:
        name, _, depth = item.partition('=')
        probes.append((name, int(depth) if depth else 0))
    if a.leaf_dir:
        a.leaf += sorted(a.leaf_dir.glob('*.v'))
    old_ports = ports_of(a.old.read_text(), a.module)
    new_ports = ports_of(a.new.read_text(), a.module)
    if old_ports != new_ports:
        raise SystemExit('port lists differ:\n%s\n%s' % (old_ports, new_ports))
    work = a.work or Path(tempfile.mkdtemp(prefix='equiv_'))
    work.mkdir(parents=True, exist_ok=True)
    old = simulate('old', a.old, a.leaf, a.module, old_ports, a.cycles, a.seed, work, a.timeout, probes)
    new = simulate('new', a.new, a.leaf, a.module, new_ports, a.cycles, a.seed, work, a.timeout, probes)
    if len(old) != len(new):
        raise SystemExit('trace lengths differ: %d vs %d' % (len(old), len(new)))
    names = [n for d, n, _ in old_ports if d == 'output']
    for name, depth in probes:
        names += ['%s[%d]' % (name, i) for i in range(depth)] if depth else [name]
    for i, (x, y) in enumerate(zip(old, new)):
        if x != y:
            xs, ys = x.split(), y.split()
            bad = [names[j] for j in range(1, len(xs)) if xs[j] != ys[j]] if len(xs) == len(ys) else ['?']
            print('MISMATCH %s cycle %s outputs %s\n old: %s\n new: %s' % (a.module, xs[0], bad, x, y))
            return 1
    print('PASS equiv %s cycles=%d seed=%d compared=%d' % (a.module, a.cycles, a.seed, len(names)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
