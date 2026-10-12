# Linux generator scoreboard failure — resolved without changing the compiler

The original full generator scoreboard failed on Ubuntu 22.04 / Icarus **11.0**
at 2 ns: q0–q3 were unknown, expected zero. Local Icarus 13 passed. Changing the
emitted initial memory loop to explicit word assignments did not resolve it.

Isolated validation branch `sfl-oracle-20261012` preserves the experiments:

| Snapshot / run | Evidence |
|---|---|
| eea8b1f / 38286792631 | Full bench fails. Reduced bench with identical generated RTL reads initialized cells/output wires correctly before reset, during reset and after parallel load. Changing read-index widths or removing clocked bank writers also leaves the reduced bench passing. |
| efc9855 / 38290064000 | Full-bench instrumentation shows internal cells=00/00/00/00 but q0–q3=xx. Replacing automatic tasks with static tasks makes every original check pass: 6065 checks, 2019 cycles. |
| 9ccdab6 / [38296978627](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38296978627) | Full 15-group regression passes on Linux with the static-task change. Independent diagnostic RTL also passes 3 frames / 618600 pixels. |

The primary fix changes only task storage in
`tools/sflc/tests/tb_generators.sv`. Calls are sequential and nonrecursive, so
automatic storage is unnecessary. No initial-state check, output comparison or
stimulus was removed. Root also reran the full 15-group suite under local Icarus
13. Compiler sources, memory semantics and generated RTL were not changed.

This establishes a tool-specific interaction with the old automatic-task bench;
it does not identify an upstream Icarus implementation defect or prove all
automatic tasks are unsafe. The diagnostic script used to separate the cases is
`tools/sflc/tests/debug_bank_init.py` on the isolated branch at efc9855. It prints
the simulator version and generated RTL, then executes reduced/full/static-task
variants. It is investigative tooling, not part of the primary regression runner.

Reproduce current positive evidence:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/tests/run_tests.py
gh run view 38290064000 --repo ollisulopuisto/PlayStation_on_FPGA --log
gh run view 38296978627 --repo ollisulopuisto/PlayStation_on_FPGA --log
```

For the failing original bench, use its f983b03 version in an isolated checkout
with Icarus 11. Do not overwrite the shared worktree or infer a failure from a
different simulator version. Experimental parallel-bank p27 **still mismatches**
the archived native compiler; wide reg_ws compatibility is also unresolved.
Neither question was changed or qualified by this simulation portability fix.
