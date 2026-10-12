#!/usr/bin/env python3
"""Reproducibly compare the supported SFL+ combinational subset with sfl2vl.

Reference Verilog is intentionally external: the archived evaluation compiler
permits generated output for personal/educational use only.
"""
import argparse
import importlib.util
import random
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SFLC_PATH = Path(__file__).with_name('sflc.py')
CASES = {
    'p01_ifelse': Path('tools/sflc/probe/p01_ifelse.sfl'),
    'p03_sel': Path('tools/sflc/probe/p03_sel.sfl'),
    'p04_ops': Path('tools/sflc/probe/p04_ops.sfl'),
    'p09_prec': Path('tools/sflc/probe/p09_prec.sfl'),
    'p11_pp': Path('tools/sflc/probe/p11_pp.sfl'),
    'p12_unops': Path('tools/sflc/probe/p12_unops.sfl'),
    'p14_any_alt': Path('tools/sflc/probe/p14_any_alt.sfl'),
    'p15_submod': Path('tools/sflc/probe/p15_submod.sfl'),
    'p16_circuit_kw': Path('tools/sflc/probe/p16_circuit_kw.sfl'),
    'p22_widths': Path('tools/sflc/probe/p22_widths.sfl'),
    'p23_call_args': Path('tools/sflc/probe/p23_call_args.sfl'),
    'p24_shared_args': Path('tools/sflc/probe/p24_shared_args.sfl'),
    'p25_selector_guards': Path('tools/sflc/probe/p25_selector_guards.sfl'),
    'p26_data_controls': Path('tools/sflc/probe/p26_data_controls.sfl'),
    'real_bsr_s16': Path('bsr_s16.sflp'),
}
DECL = re.compile(
    r'^\s*(input|output)\s*(?:\[(\d+)\s*:\s*(\d+)\])?\s*([^;]+);',
    re.MULTILINE,
)


class CosimError(Exception):
    pass


def load_sflc():
    spec = importlib.util.spec_from_file_location('sflc_under_test', SFLC_PATH)
    if spec is None or spec.loader is None:
        raise CosimError('cannot import tools/sflc/sflc.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_ports(verilog, label):
    """Read the simple non-ANSI port declarations emitted by both compilers."""
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', verilog, flags=re.DOTALL)
    module = re.search(r'\bmodule\s+(\w+)\s*\((.*?)\)\s*;', text, re.DOTALL)
    if not module:
        raise CosimError('%s: could not parse plain module header' % label)
    header = [name.strip() for name in module.group(2).split(',') if name.strip()]
    ports = {}
    for match in DECL.finditer(text):
        direction, msb, lsb, names = match.groups()
        width = abs(int(msb) - int(lsb)) + 1 if msb is not None else 1
        for name in names.split(','):
            name = name.strip().split()[-1]
            if not re.fullmatch(r'\w+', name):
                raise CosimError('%s: unsupported port declaration %r' % (label, name))
            if name in ports:
                raise CosimError('%s: duplicate port %s' % (label, name))
            ports[name] = (direction, width)
    missing = [name for name in header if name not in ports]
    if missing:
        raise CosimError('%s: no direction/width for ports %s' % (label, ', '.join(missing)))
    return module.group(1), header, ports


def rename_module(verilog, new_name, label):
    text, count = re.subn(r'(\bmodule\s+)\w+', r'\g<1>' + new_name, verilog, count=1)
    if count != 1:
        raise CosimError('%s: failed to rename generated module' % label)
    return text


def literal(value, width):
    digits = max(1, (width + 3) // 4)
    return "%d'h%0*x" % (width, digits, value)


def make_fixture(name, ref_text, dut_text, rng, vectors):
    ref_name, ref_header, ref_ports = parse_ports(ref_text, name + ' reference')
    _, dut_header, dut_ports = parse_ports(dut_text, name + ' DUT')
    for special in ('p_reset', 'm_clock'):
        ref_ports.pop(special, None)
        dut_ports.pop(special, None)
    ref_inputs = {p: w for p, (d, w) in ref_ports.items() if d == 'input'}
    dut_inputs = {p: w for p, (d, w) in dut_ports.items() if d == 'input'}
    ref_outputs = {p: w for p, (d, w) in ref_ports.items() if d == 'output'}
    dut_outputs = {p: w for p, (d, w) in dut_ports.items() if d == 'output'}
    if ref_inputs != dut_inputs or ref_outputs != dut_outputs:
        raise CosimError('%s: port mismatch reference inputs/outputs=%r/%r DUT=%r/%r' %
                         (name, ref_inputs, ref_outputs, dut_inputs, dut_outputs))
    if not ref_outputs:
        raise CosimError('%s: expected at least one output' % name)

    lines = ['module tb_%s;' % name]
    for port, width in ref_inputs.items():
        lines.append('  reg [%d:0] in_%s;' % (width - 1, port))
    for port, width in ref_outputs.items():
        lines.append('  wire [%d:0] ref_%s;' % (width - 1, port))
        lines.append('  wire [%d:0] dut_%s;' % (width - 1, port))
    for inst, module_name in (('ref_i', ref_name), ('dut_i', '__cosim_dut_' + name)):
        conns = []
        header = ref_header if inst == 'ref_i' else dut_header
        for port in header:
            if port == 'p_reset': conns.append('.p_reset(1\'b0)')
            elif port == 'm_clock': conns.append('.m_clock(1\'b0)')
            elif port in ref_inputs: conns.append('.%s(in_%s)' % (port, port))
            elif port in ref_outputs: conns.append('.%s(%s_%s)' % ('%s' % port, 'ref' if inst == 'ref_i' else 'dut', port))
            else: raise CosimError('%s: unsupported port %s' % (name, port))
        lines.append('  %s %s (%s);' % (module_name, inst, ', '.join(conns)))
    lines.append('  initial begin')
    for index in range(vectors):
        for port, width in ref_inputs.items():
            lines.append('    in_%s = %s;' % (port, literal(rng.getrandbits(width), width)))
        lines.append('    #1;')
        for port in ref_outputs:
            lines.append('    if (ref_%s !== dut_%s) $fatal(1, "mismatch case=%d port=%s ref=%%h dut=%%h", ref_%s, dut_%s);' %
                         (port, port, index, port, port, port))
    lines += ['    $display("PASS %s vectors=%d");' % (name, vectors), '    $finish;', '  end', 'endmodule', '']
    return '\n'.join(lines)


def run_case(name, source_rel, reference_dir, vectors, rng, iverilog, vvp, timeout):
    source_path = ROOT / source_rel
    reference_path = reference_dir / (name + '.v')
    if not source_path.is_file():
        raise CosimError('%s: missing source %s' % (name, source_path))
    if not reference_path.is_file():
        raise CosimError('%s: missing reference %s' % (name, reference_path))
    try:
        reference = reference_path.read_text(encoding='utf-8')
        dut = load_sflc().translate(str(source_path))
    except (OSError, UnicodeError, NotImplementedError, ValueError, NameError, SyntaxError) as exc:
        raise CosimError('%s: translation/reference read failed: %s' % (name, exc)) from exc
    dut = rename_module(dut, '__cosim_dut_' + name, name)
    fixture = make_fixture(name, reference, dut, rng, vectors)
    with tempfile.TemporaryDirectory(prefix='sflc-cosim-') as tmp:
        tmp_path = Path(tmp)
        tb_path = tmp_path / 'tb.sv'
        exe_path = tmp_path / 'sim.out'
        tb_path.write_text(fixture, encoding='utf-8')
        dut_path = tmp_path / 'dut.sv'
        dut_path.write_text(dut, encoding='utf-8')
        try:
            subprocess.run([iverilog, '-g2012', '-s', 'tb_' + name, '-o', str(exe_path),
                            str(reference_path), str(dut_path), str(tb_path),
                            *([str(ROOT/'tools/sflc/tests/interface_leaf.sv')]
                              if name == 'p15_submod' else [])],
                           check=True, capture_output=True, text=True, timeout=timeout)
            result = subprocess.run([vvp, str(exe_path)], check=True, capture_output=True,
                                    text=True, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise CosimError('%s: %s timed out after %ss' % (name, exc.cmd[0], timeout)) from exc
        except subprocess.CalledProcessError as exc:
            detail = (exc.stdout or '') + (exc.stderr or '')
            raise CosimError('%s: command failed (%s):\n%s' % (name, exc.returncode, detail.strip())) from exc
        marker = 'PASS %s vectors=%d' % (name, vectors)
        if marker not in result.stdout:
            raise CosimError('%s: simulator exited successfully without %r; output:\n%s' %
                             (name, marker, result.stdout.strip()))
    print(marker)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-dir', type=Path, default=None,
                        help='directory containing archived <case>.v outputs (required)')
    parser.add_argument('--vectors', type=int, default=4000)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--timeout', type=int, default=120, help='timeout seconds per compiler/simulator')
    args = parser.parse_args(argv)
    if args.vectors <= 0 or args.timeout <= 0:
        parser.error('--vectors and --timeout must be positive')
    if args.reference_dir is None:
        parser.error('--reference-dir is required; licensed reference Verilog is not included')
    reference_dir = args.reference_dir.expanduser().resolve()
    if not reference_dir.is_dir():
        parser.error('reference directory does not exist: %s' % reference_dir)
    iverilog, vvp = shutil.which('iverilog'), shutil.which('vvp')
    if not iverilog or not vvp:
        print('cosim: iverilog and vvp must both be available on PATH', file=sys.stderr)
        return 2
    rng = random.Random(args.seed)
    try:
        for name, source in CASES.items():
            run_case(name, source, reference_dir, args.vectors, rng, iverilog, vvp, args.timeout)
    except CosimError as exc:
        print('cosim: %s' % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
