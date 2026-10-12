#!/usr/bin/env python3
"""Compare sequential SFL probes with externally generated sfl2vl oracles.

Reference Verilog is intentionally external; the archived evaluation compiler
permits generated output for personal/educational use only. Run with
--reference-dir pointing at the oracle output directory.
"""
import argparse
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import sflc
from cosim import CosimError, literal, parse_ports, rename_module

CASES = {
    "p17_registers": Path("tools/sflc/probe/p17_registers.sfl"),
    "p18_controls": Path("tools/sflc/probe/p18_controls.sfl"),
    "p19_stage": Path("tools/sflc/probe/p19_stage.sfl"),
    "p20_retained_stage": Path("tools/sflc/probe/p20_retained_stage.sfl"),
    "p21_multi_task": Path("tools/sflc/probe/p21_multi_task.sfl"),
    "p28_generator_controls": Path("tools/sflc/tests/generator_controls.sflp"),
    "p27_parallel_memory": Path("tools/sflc/tests/generators.sflp"),
}
TIMEOUT = 120


def fixture(name, reference, dut, rng, cycles):
    ref_name, ref_header, ref_ports = parse_ports(reference, name + " reference")
    _, dut_header, dut_ports = parse_ports(dut, name + " DUT")
    for special in ("p_reset", "m_clock"):
        if ref_ports.get(special, (None,))[0] != "input" or dut_ports.get(special, (None,))[0] != "input":
            raise CosimError("%s: expected %s input on both modules" % (name, special))
        ref_ports.pop(special)
        dut_ports.pop(special)
    ref_inputs = {port: width for port, (direction, width) in ref_ports.items() if direction == "input"}
    dut_inputs = {port: width for port, (direction, width) in dut_ports.items() if direction == "input"}
    ref_outputs = {port: width for port, (direction, width) in ref_ports.items() if direction == "output"}
    dut_outputs = {port: width for port, (direction, width) in dut_ports.items() if direction == "output"}
    if ref_inputs != dut_inputs or ref_outputs != dut_outputs:
        raise CosimError("%s: reference/DUT ports differ (inputs %r/%r, outputs %r/%r)" %
                         (name, ref_inputs, dut_inputs, ref_outputs, dut_outputs))
    if not ref_outputs:
        raise CosimError(name + ": expected at least one output")

    lines = ["module tb_%s;" % name, "  reg clk=0, rst=0;"]
    for port, width in ref_inputs.items():
        lines.append("  reg [%d:0] in_%s;" % (width - 1, port))
    for port, width in ref_outputs.items():
        lines.append("  wire [%d:0] ref_%s, dut_%s;" % (width - 1, port, port))
    for instance, module_name, header, prefix in (
            ("ref_i", ref_name, ref_header, "ref"),
            ("dut_i", "__cosim_dut_" + name, dut_header, "dut")):
        conns = []
        for port in header:
            if port == "p_reset":
                conns.append(".p_reset(rst)")
            elif port == "m_clock":
                conns.append(".m_clock(clk)")
            elif port in ref_inputs:
                conns.append(".%s(in_%s)" % (port, port))
            elif port in ref_outputs:
                conns.append(".%s(%s_%s)" % (port, prefix, port))
            else:
                raise CosimError("%s: unsupported port %s" % (name, port))
        lines.append("  %s %s (%s);" % (module_name, instance, ", ".join(conns)))

    def check(cycle, phase):
        lines.append("    #1;")
        for port in ref_outputs:
            lines.append('    if (ref_%s !== dut_%s) $fatal(1, "mismatch case=%s phase=%s cycle=%%0d port=%s ref=%%h dut=%%h", %d, ref_%s, dut_%s);' %
                         (port, port, name, phase, port, cycle, port, port))

    lines.append("  initial begin")
    for port, width in ref_inputs.items():
        lines.append("    in_%s = %s;" % (port, literal(0, width)))
    # Force an asynchronous reset edge before the first clock and compare both
    # the reset state and the state after reset is released.
    lines.extend(["    #1; rst=1;"])
    check(0, "async_reset")
    lines.append("    rst=0;")
    check(0, "reset_released")

    for cycle in range(cycles):
        values = {port: rng.getrandbits(width) for port, width in ref_inputs.items()}
        for port, width in ref_inputs.items():
            lines.append("    in_%s = %s;" % (port, literal(values[port], width)))
        if cycle % 97 == 0:
            lines.append("    rst=1;")
            check(cycle, "periodic_async_reset")
            lines.append("    rst=0;")
            check(cycle, "periodic_reset_released")
        check(cycle, "pre_edge")
        lines.append("    clk=1;")
        check(cycle, "post_edge")
        lines.append("    clk=0;")
        check(cycle, "post_fall")
    lines += ['    $display("PASS %s cycles=%d");' % (name, cycles),
              "    $finish;", "  end", "endmodule", ""]
    return "\n".join(lines)


def run_case(name, reference_dir, rng, cycles, iverilog, vvp, timeout):
    source_path = ROOT / CASES[name]
    reference_path = reference_dir / (name + ".v")
    if not source_path.is_file():
        raise CosimError("%s: missing source %s" % (name, source_path))
    if not reference_path.is_file():
        raise CosimError("%s: missing oracle file %s" % (name, reference_path))
    try:
        reference = reference_path.read_text(encoding="utf-8")
        dut = sflc.translate(source_path, assertions=False,
                             register_banks=(name == 'p27_parallel_memory'))
        dut = rename_module(dut, "__cosim_dut_" + name, name)
        testbench = fixture(name, reference, dut, rng, cycles)
    except (OSError, UnicodeError, NotImplementedError, ValueError, NameError, SyntaxError, CosimError) as exc:
        raise CosimError("%s: compile fixture preparation failed: %s" % (name, exc)) from exc

    with tempfile.TemporaryDirectory(prefix="sflc-sequential-cosim-") as temp:
        build = Path(temp)
        dut_path = build / "dut.sv"
        bench_path = build / "tb.sv"
        exe_path = build / "sim.out"
        dut_path.write_text(dut, encoding="utf-8")
        bench_path.write_text(testbench, encoding="utf-8")
        try:
            subprocess.run([iverilog, "-g2012", "-s", "tb_" + name, "-o", str(exe_path),
                            str(reference_path), str(dut_path), str(bench_path)],
                           check=True, capture_output=True, text=True, timeout=timeout)
            result = subprocess.run([vvp, str(exe_path)], check=True, capture_output=True,
                                    text=True, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise CosimError("%s: %s timed out after %ss" % (name, exc.cmd[0], timeout)) from exc
        except subprocess.CalledProcessError as exc:
            output = (exc.stdout or "") + (exc.stderr or "")
            raise CosimError("%s: command failed (%s):\n%s" %
                             (name, exc.returncode, output.strip())) from exc
        marker = "PASS %s cycles=%d" % (name, cycles)
        if marker not in result.stdout:
            raise CosimError("%s: simulator exited without %r; output:\n%s" %
                             (name, marker, result.stdout.strip()))
    print(marker, flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-dir", type=Path, required=True,
                        help="directory containing external <case>.v oracle files")
    parser.add_argument("--cycles", type=int, default=4000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--cases", nargs="+", choices=tuple(CASES),
                        default=[name for name in CASES if name != 'p27_parallel_memory'],
                        help="probe subset; p27 is an opt-in known mismatch for experimental register banks")
    parser.add_argument("--timeout", type=int, default=TIMEOUT, help="seconds per compile/simulation")
    args = parser.parse_args(argv)
    if args.cycles <= 0 or args.timeout <= 0:
        parser.error("--cycles and --timeout must be positive")
    reference_dir = args.reference_dir.expanduser().resolve()
    if not reference_dir.is_dir():
        parser.error("reference directory does not exist: %s" % reference_dir)
    iverilog, vvp = shutil.which("iverilog"), shutil.which("vvp")
    if not iverilog or not vvp:
        print("cosim_sequential: iverilog and vvp must both be available on PATH", file=sys.stderr)
        return 2
    rng = random.Random(args.seed)
    try:
        for name in args.cases:
            run_case(name, reference_dir, rng, args.cycles, iverilog, vvp, args.timeout)
    except CosimError as exc:
        print("cosim_sequential: %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
