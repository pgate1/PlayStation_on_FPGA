#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Bounded compiler/block regression. No proprietary compiler required.

Run from any directory: python3 tools/sflc/tests/run_tests.py
Includes deliberately reverted cache fixes; those runs MUST fail.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/sflc'))
import sflc
import sflp_parse


class CompilerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for tool in ('iverilog', 'vvp'):
            if not shutil.which(tool): raise RuntimeError('required tool missing: ' + tool)
        cls.temp = tempfile.TemporaryDirectory(prefix='psx-sflc-')
        cls.build = Path(cls.temp.name)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def compile_text(self, text, name='fixture', assertions=True):
        source = self.build / (name + '.sflp')
        source.write_text(text)
        return sflc.translate(source, assertions=assertions)

    def simulate(self, top, sources, bench):
        paths = []
        for name, text in sources.items():
            p = self.build / (name + '.sv'); p.write_text(text); paths.append(str(p))
        out = self.build / (top + '.vvp')
        subprocess.run(['iverilog', '-g2012', '-s', top, '-o', str(out), *paths, str(bench)],
                       check=True, capture_output=True, text=True, timeout=30)
        return subprocess.run(['vvp', str(out)], capture_output=True, text=True, timeout=30)

    def test_01_parse_original_sources(self):
        files = sorted(ROOT.rglob('*.sflp'))
        for path in files:
            with self.subTest(path=path.relative_to(ROOT)):
                sflp_parse.parse_file(path, ())

    def test_02_sequential_behavior(self):
        result = self.simulate('tb_sequential', {'sequential': sflc.translate(
            ROOT/'tools/sflc/tests/sequential.sflp', assertions=True)},
            ROOT/'tools/sflc/tests/tb_sequential.sv')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS sequential cycles=4000', result.stdout)

    def test_03_cache_behavior_and_mutants(self):
        sources = {n: sflc.translate(ROOT/(n+'.sflp'), assertions=True)
                   for n in ('Cache_IR', 'Cache_Texture')}
        bench = ROOT/'tools/sflc/tests/tb_caches.sv'
        result = self.simulate('tb_caches', sources, bench)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS caches checks=242', result.stdout)
        for name in sources:
            # Mutate a temporary source copy; never touch the user's SFL bytes.
            text = (ROOT/(name+'.sflp')).read_bytes().decode('latin1')
            good = '((offset==0)|(offset==1)|(offset==2))'
            self.assertEqual(text.count(good), 1)
            bad = text.replace(good, '((offset==0)|(offset==0)|(offset==2))')
            source = self.build/(name+'.sflp'); source.write_bytes(bad.encode('latin1'))
            mutated = dict(sources, **{name: sflc.translate(source, assertions=True)})
            result = self.simulate('tb_caches', mutated, bench)
            self.assertNotEqual(result.returncode, 0, 'cache mutation escaped: '+name)
            self.assertIn('FATAL:', result.stdout)
            self.assertIn('IR hit address=' if name=='Cache_IR' else 'texture expected hit', result.stdout)
            print('Detected reverted suffix comparison:', name, flush=True)

    def test_04_supported_real_modules_elaborate(self):
        names = ['Cache_IR', 'Cache_Texture', 'DDS_50to33868800', 'DMA_GPU', 'DMA_OTC',
                 'MDEC', 'Scratchpad', 'Timer', 'VGA_ctrl', 'bsr_s16', 'bsr_s24', 'bsr_s32',
                 'div_u32', 'dsdac10', 'gte_LIMIT', 'inv_table', 'ram_16x32k',
                 'ram_320x240x15', 'ram_8x2352']
        for name in names:
            with self.subTest(module=name):
                out = self.build/(name+'.sv')
                out.write_text(sflc.translate(ROOT/(name+'.sflp'), assertions=True))
                subprocess.run(['iverilog', '-g2012', '-s', name, '-t', 'null', str(out)],
                               check=True, capture_output=True, text=True, timeout=30)

    def test_05_errors_are_explicit(self):
        bad = [
            ('input a; a = 0;', ValueError),
            ('output a; a := 0;', ValueError),
            ('reg a; a = 0;', ValueError),
            ('output a; a = missing;', NameError),
            ('input a; output b; b=a<1>;', ValueError),
            ('sel a<0>;', ValueError),
            ('mem a[0]<8>;', ValueError),
            ('mem a[1]<8>={1,2};', ValueError),
            ('input a; switch(a){case 0:;case 0:;}', ValueError),
            ('input a; switch(a){case 2:;}', ValueError),
            ('instrin a; a();', ValueError),
            ('instrself a(x); sel x; a();', ValueError),
            ('finish;', ValueError),
            ('stage_name s {task do();} stage s {first_state x; state x goto missing;}', NameError),
            ('stage_name s {task a(); task a();}', ValueError),
            ('input a; sel a;', ValueError),
            ('sel __sfl_bad;', ValueError),
            ('output a; a=1#0xFF;', ValueError),
            ('input n<4>; par(i=0;i<n;i++){;}', NotImplementedError),
            ('par(i=0;i<4;j++){;}', SyntaxError),
            ('par(i=0;i<4097;i++){;}', ValueError),
            ('par(i=0-1;i<4;i++){;}', ValueError),
            ('mem a[2]<8>; a[2]:=0;', ValueError),
            ('alt(i=0;i<0;i++){ 0b1:; else: if(i==0); }', NameError),
            ('output a; bus b; a=b;', NotImplementedError),
        ]
        for body, error in bad:
            with self.subTest(body=body):
                with self.assertRaises(error): self.compile_text('circuit bad {'+body+'}')
        with self.assertRaises(FileNotFoundError):
            self.compile_text('%i "missing.h"\ncircuit bad {}')

    def test_06_conflicts_trip_at_runtime(self):
        dut = self.compile_text('circuit conflict {input a,b; reg_wr r<8>; '
                                'if(a) r:=0x12; if(b) r:=0x34;}')
        bench = self.build/'tb_conflict.sv'
        bench.write_text('module tb_conflict; reg clk=0,rst=0,a=0,b=0; '
                         'conflict d(.m_clock(clk),.p_reset(rst),.a(a),.b(b)); '
                         'initial begin #1;rst=1;#1;rst=0;a=1;b=1;#1;clk=1;'
                         '#2;$fatal(1,"missed conflict");end endmodule')
        result = self.simulate('tb_conflict', {'conflict': dut}, bench)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('conflicting drivers: r', result.stdout)

    def test_07_scopes_and_forward_declarations(self):
        code = self.compile_text('circuit scopes { output a<8>,b<8>; '
                                 'if(0b1){a=x;sel x<8>;x=3;} '
                                 'if(0b1){sel x<8>;x=5;b=x;}}')
        bench = self.build/'tb_scopes.sv'
        bench.write_text('module tb_scopes; wire [7:0] a,b; '
                         'scopes d(.p_reset(1\'b0),.m_clock(1\'b0),.a(a),.b(b));'
                         'initial begin #1;if(a!==3||b!==5)$fatal(1,"scope leak");'
                         '$display("PASS scopes");$finish;end endmodule')
        result = self.simulate('tb_scopes', {'scopes': code}, bench)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS scopes', result.stdout)

    def test_08_widths_and_numeric_boundaries(self):
        result = self.simulate('tb_widths', {'widths': sflc.translate(
            ROOT/'tools/sflc/tests/widths.sflp', assertions=True)},
            ROOT/'tools/sflc/tests/tb_widths.sv')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS widths vectors=65536', result.stdout)

    def test_09_supported_probes_elaborate(self):
        unsupported = {'p08_gen', 'p27_parallel_memory'}
        for path in sorted((ROOT/'tools/sflc/probe').glob('p*.sfl')):
            with self.subTest(probe=path.name):
                if path.stem in unsupported:
                    with self.assertRaises(NotImplementedError): sflc.translate(path)
                    continue
                out = self.build/(path.stem+'.sv')
                out.write_text(sflc.translate(path, assertions=True))
                extras = [str(ROOT/'tools/sflc/tests/interface_leaf.sv')] if path.stem == 'p15_submod' else []
                subprocess.run(['iverilog', '-g2012', '-t', 'null', str(out), *extras],
                               check=True, capture_output=True, text=True, timeout=30)

    def test_10_linked_clocked_and_interface_modules(self):
        generated = sflc.translate(ROOT/'tools/sflc/tests/hierarchy/linked.sflp',
                                   assertions=True, hierarchy=True)
        leaf = (ROOT/'tools/sflc/tests/interface_leaf.sv').read_text()
        result = self.simulate('tb_linked', {'linked_hierarchy': generated, 'leaf': leaf},
                               ROOT/'tools/sflc/tests/hierarchy/tb_linked.sv')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS linked cycles=2000', result.stdout)
        self.assertEqual(generated.count('module holding_child ('), 1)

    def test_12_overlapping_stage_tasks(self):
        result = self.simulate('tb_multi_task', {'p21': sflc.translate(
            ROOT/'tools/sflc/probe/p21_multi_task.sfl', assertions=False)},
            ROOT/'tools/sflc/tests/tb_multi_task.sv')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS multi-task checks=40', result.stdout)

    def test_13_instruction_argument_connections(self):
        modules = {name: sflc.translate(ROOT/('tools/sflc/probe/'+name+'.sfl'))
                   for name in ('p18_controls', 'p23_call_args', 'p24_shared_args',
                                'p25_selector_guards', 'p26_data_controls')}
        result = self.simulate('tb_call_args', modules, ROOT/'tools/sflc/tests/tb_call_args.sv')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS call arguments checks=4096', result.stdout)

    def test_14_generators_and_parallel_memory(self):
        with self.assertRaisesRegex(NotImplementedError, 'experimental --register-banks'):
            sflc.translate(ROOT/'tools/sflc/tests/generators.sflp')
        result = self.simulate('tb_generators', {'p27': sflc.translate(
            ROOT/'tools/sflc/tests/generators.sflp', assertions=False, register_banks=True)},
            ROOT/'tools/sflc/tests/tb_generators.sv')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('PASS generators checks=6065 cycles=2019', result.stdout)

    def test_15_gte_hierarchy_elaborates(self):
        out = self.build/'gte_hierarchy.sv'
        out.write_text(sflc.translate(ROOT/'GeometryTransformationEngine.sflp',
                                     hierarchy=True, register_banks=True))
        subprocess.run(['iverilog', '-g2012', '-s', 'GeometryTransformationEngine', '-t', 'null',
                        str(out), *[str(ROOT/n) for n in ('mul_s16.v', 'mul_s32.v', 'mul_u32.v')]],
                       check=True, capture_output=True, text=True, timeout=30)

    def test_11_linker_rejects_bad_interfaces(self):
        header = 'declare child interface {input a<8>; output b<8>; instrin put(a); instrout ack;}'
        for body, error in [
            ('child c; c.b=0;', ValueError),
            ('child c; c.ack();', ValueError),
            ('child c; c.put();', ValueError),
            ('child c; output o; o=c.missing;', NameError),
            ('missing c;', NameError),
            ('child c; instruct c.b ;', ValueError),
        ]:
            with self.subTest(body=body):
                with self.assertRaises(error):
                    self.compile_text(header+'circuit bad {'+body+'}')
        with self.assertRaisesRegex(ValueError, 'conflicting declarations'):
            self.compile_text(header+'declare child interface {input a<7>;} circuit bad {}')
        source = self.build/'recursive.sflp'
        source.write_text('%i "recursive.h"\ncircuit recursive {recursive child;}')
        with self.assertRaisesRegex(ValueError, 'recursive module'):
            sflc.translate(source, hierarchy=True)
        source.write_text('%i "cycle_a.h"\ncircuit recursive {}')
        (self.build/'cycle_a.h').write_text('%i "cycle_b.h"')
        (self.build/'cycle_b.h').write_text('%i "cycle_a.h"')
        with self.assertRaisesRegex(ValueError, 'cyclic header'):
            sflc.translate(source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
