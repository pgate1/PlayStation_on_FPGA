#!/usr/bin/env python3
"""Boundary checks for constant-indexed SFL+ instances.

Run independently with:
    python3 tools/sflc/tests/test_instance_array_boundaries.py

Each input is written to a temporary directory and compiled through the public
``sflc.translate`` entrypoint. No real source file or shared runner is changed.
"""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "sflc"))
import sflc


IFACE = """declare leaf interface {
    input x<8>;
    output q<8>;
    instrin con(x);
}
"""


class InstanceArrayBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sflc-instance-boundary-")
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def compile(self, body, header=IFACE):
        source = self.root / "case.sflp"
        source.write_text(header + "\ncircuit boundary_case {\n" + body + "\n}\n")
        return sflc.translate(source)

    def test_valid_uppercase_hex_and_padded_suffix_routes_to_declared_instance(self):
        generated = self.compile("""
            input d<8>;
            output y<8>;
            leaf node_00, node_0A, node_10;
            y = node[10].con(d).q;
        """)
        expected = "assign y = (__sfl_port_1_q);"
        self.assertIn(expected, generated)

        # Deliberate wrong-map mutant: route element 10 to element 0. The
        # routing expectation above must reject this generated output.
        wrong_map = generated.replace(expected, "assign y = (__sfl_port_0_q);")
        self.assertNotEqual(generated, wrong_map)
        self.assertNotIn(expected, wrong_map)

    def test_missing_element_is_rejected(self):
        with self.assertRaisesRegex(NameError, r"undeclared instance s_1"):
            self.compile("""
                input d<8>;
                leaf s_0, s_2;
                par(i=0; i<2; i++) { s[i].con(d); }
            """)

    def test_negative_index_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "negative instance index"):
            self.compile("input d<8>; leaf s_0, s_1; s[0-1].con(d);")

    def test_mixed_suffix_widths_are_ambiguous(self):
        with self.assertRaisesRegex(ValueError, "ambiguous instance array"):
            self.compile("input d<8>; leaf s_0, s_00; s[0].con(d);")

    def test_runtime_index_is_rejected(self):
        with self.assertRaisesRegex(NotImplementedError, "nonconstant"):
            self.compile("input n<2>, d<8>; leaf s_0, s_1; s[n].con(d);")

    def test_ordinary_indexed_memory_remains_a_memory_access(self):
        generated = self.compile("""
            output y<8>;
            mem cells[2]<8> = {0};
            y = cells[0];
        """)
        self.assertIn("assign y = (cells[1'd0]);", generated)
        self.assertNotIn("cells_0", generated)

    def test_scalar_index_stays_an_index_but_method_qualifier_selects_instance(self):
        # Bare s[0] keeps ordinary signal/memory indexing rules. The member
        # qualifier on s[0].con(...) identifies the declared component s_0.
        with self.assertRaisesRegex(NotImplementedError, "index of non-memory"):
            self.compile("input s<8>; leaf s_0; output y<8>; y = s[0];")
        generated = self.compile("input s<8>, d<8>; leaf s_0; output y<8>; y = s[0].con(d).q;")
        self.assertIn("input [7:0] s;", generated)
        self.assertIn("leaf s_0", generated)
        self.assertIn("assign y = (__sfl_port_0_q);", generated)

    def test_method_result_inside_generator_routes_each_expanded_instance(self):
        generated = self.compile("""
            input d<8>;
            output y<8>;
            leaf ch_00, ch_01;
            any(i=0; i<2; i++) {
                i==0 : y = ch[i].con(d).q;
                else : y = 0;
            }
        """)
        self.assertIn("leaf ch_00", generated)
        self.assertIn("leaf ch_01", generated)
        self.assertIn("__sfl_port_0_q", generated)
        self.assertIn("__sfl_port_1_q", generated)

    def test_nested_method_call_on_prior_result_is_unsupported(self):
        with self.assertRaisesRegex(NotImplementedError, "nested call result"):
            self.compile("""
                input d<8>;
                output y<8>;
                leaf ch_00;
                y = ch[0].con(d).q.con(d).q;
            """)


if __name__ == "__main__":
    unittest.main(verbosity=2)
