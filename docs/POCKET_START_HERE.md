# Session checkpoint — start here

Updated **2026-10-12**. Latest handoff: [POCKET_HANDOFF_2026-10-12.md](POCKET_HANDOFF_2026-10-12.md).
Workspace:
`/Users/dst/Documents/koodi/PlayStation_on_FPGA-master`.

## Objective and work order

Improve this PS1 FPGA core for Analogue Pocket: correct game speed and roughly
**30 newly rendered frames/s** in selected simple original PS1 games, then sound.
Video first; reserve resources and memory service for later audio. Do not confuse
output refresh or repeated frames with newly rendered frames.

The user authorized autonomous implementation of the hardest work and wants
small, explicit L1/L2 task packets for simpler models across providers. Those
packets are in [POCKET_MODEL_HANDOFF.md](POCKET_MODEL_HANDOFF.md). One integrator
must own compiler semantics and shared RTL interfaces.

## Current state — supersedes older checkpoint claims

This is now a Git checkout, with existing committed and uncommitted work. Check
`git status` before editing. Milestone commit `6fbe8bc` contains the first compiler/cache work; external agent
commit `95d42dd` adds the portable HDL runner. Isolated validation branch
`sfl-oracle-20261012` was pushed for Linux reference/regression runs; integration
checkpoint `0422745` adds hierarchy linking, stages and the task queue.
Checkpoint `e92456c` commits the 32-probe matrix; its checker passes, though
p21 and oracle-status rows still need updating.
The preceding selector checkpoint `d93175d` matches native p23–p26; its 13-group
regression passes Linux CI run `38222767443` (snapshot `c2da886`).
Preserve the original SFL files' CRLF/non-UTF-8 bytes. This session changed compiler,
fixtures and documentation, not the cache source bytes or the live Pocket top.

| Area | Actual evidence |
|---|---|
| Replacement SFL compiler | Expanded from combinational subset to registers, memory, local controls, lexical scopes, switch, multiple-task stages and hierarchy linking; **experimental**, not a full compiler |
| P02 caches | Actual corrected SFL sources compile and pass 242 behavioral checks; reverting each existing suffix comparison makes the bench fail |
| Compiler validation | Thirteen test groups pass, including 4,000 sequential cycles and 65,536 arithmetic vectors; 19 real leaf modules elaborate; linked fixture passes 2,000 cycles |
| Reference equivalence | Fifteen combinational cases pass 4,000 vectors each; all five sequential cases pass 4,000 cycles each; sampled p18/p23–p26 selector mismatches fixed |
| Cache lint | Both generated caches pass Verilator 5.052 without warnings |
| P04 memory frontend | Isolated behavioral scoreboard already passed across multiple parameter sets; not integrated |
| Replacement framebuffer RAM/SRAM blocks | Written and previously simulated; interface/timing assumptions remain |
| Recovered dependencies | UART files and pinned MIRLO controller/PHY imported; APF fetch script exists |
| Complete Pocket build, fit, timing, hardware FPS | **Not achieved or measured** |

Read [POCKET_SFLC.md](POCKET_SFLC.md) for exact compiler coverage, commands,
assumptions and the next hard tasks. [POCKET_IMPLEMENTATION.md](POCKET_IMPLEMENTATION.md)
contains memory and earlier dependency evidence; historical sections there
contain superseded status statements and are labeled accordingly.

## Immediate next hard job: P00 sequential semantics and hierarchy

The compiler now makes isolated cache validation possible without a proprietary
license. Do not spend the next session redoing the parser spike or claiming that
all sequential semantics have been recovered.

1. Continue the selector/typed-expression audit described in
   [POCKET_SFLC.md](POCKET_SFLC.md). Native register, stage and sampled selector
   probes now agree, including inactive data, restart and overlapping starts.
2. Expand finite-width expression evidence beyond p22 before trusting CPU/GTE.
3. Implement constant generators and audit the linked hierarchy. Source defects
   are inventoried separately; do not silently introduce implicit signals.
4. Progress the independent [Pocket diagnostic milestone](POCKET_DIAGNOSTIC_PLAN.md).
   [Authoritative inputs](POCKET_DIAGNOSTIC_INPUTS.md) are now recovered; the
   smaller-model RTL/simulation task is ready. Quartus still gates fitting.
   Its test pattern/input response does not prove game execution.
5. Keep the frontend isolated and the existing CPU/GPU stalls in place until the
   platform/controller integration prerequisites are met.

Run current local evidence:

```sh
python3 tools/sflc/tests/run_tests.py
```

The optional reference regression is
`python3 tools/sflc/cosim.py --reference-dir /path/to/sfl2vl-probe-out`.
Existing reference files were recovered from the earlier local Claude scratch
`ci2/sfl2vl-probe-out` directory; they are not vendored. A fresh checkout needs
external reference artifacts to run that optional comparison.

Python 3.12, Icarus 13.0, vvp and Verilator 5.052 were available in this session.
A working Quartus installation was not established. `sflp` is still unavailable;
the archived sfl2vl is a Linux i386 evaluation binary with a 500-line limit.
Do not evade that limit. See [P00 toolchain history](POCKET_P00_TOOLCHAIN.md).

## Integration blockers that still matter

- No complete Pocket QPF/QSF/SDC project or verified PLL clock/phase setup.
- The missing original SDRAM controller's ack convention is unresolved. Imported
  MIRLO controller/PHY files are pinned but not adapted to Pocket's clocks.
- `core_top.v` OR-combines loader/core memory commands. The core broadcasts some
  acknowledgements. Request ownership must be fixed end to end.
- Memory controller/core clocks differ; bundled request data and loader bridge
  traffic need coherent CDC/queueing. One synchronized strobe is insufficient.
- Frontend, adapter, controller and producer transaction state need a common
  reset/flush contract. Do not allow stale completions after reset.
- `core_top.v` still references BRAM interfaces commented out in `core.sflp`.
  Newly written RAM/SRAM replacements use inferred interfaces pending integration.
- APF files are fetched at build time with hashes; release redistribution remains
  a separate unresolved item. The fetch script's existence is not a full build.

For ownership/byte-lane rules read [POCKET_MEMORY_CONTRACT.md](POCKET_MEMORY_CONTRACT.md).
Do not remove `gpu.drawing` stalls or wire speculative adapters into the top and
call P04 complete.

## After build recovery

P06 remains the major resource opportunity: historical utilization was 307/308
RAM blocks and 17,060/18,480 ALMs. Two full internal display buffers consume most
of the reclaimable RAM. Rendering must first make real PS1 VRAM authoritative;
external scanout alone does not fix the renderers' view-buffer shortcuts. Keep
resource and bandwidth budgets for sound. Follow [POCKET_ROADMAP.md](POCKET_ROADMAP.md)
and [POCKET_BENCHMARKS.md](POCKET_BENCHMARKS.md).

The neighboring MIRLO64 tree is a read-only reference for this project; do not
overwrite its changing work. Imported source identity is recorded in
`hdl/SDRAM/MIRLO64/README.md`. MIRLO's guest CPU is MIPS VR4300-class, not RISC-V.
PSP is not the target of this work.
