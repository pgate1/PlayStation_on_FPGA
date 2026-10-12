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
Checkpoint `e92456c` commits the 32-probe matrix; its checker passed at that
checkpoint. It now needs p27/p28 rows plus p21 and oracle-status corrections.
The selector checkpoint `d93175d` matches native p23–p26. Latest compiler
checkpoint **f983b03** adds bounded generators, p28 comparison and opt-in banks.
All 15 groups pass locally; current Linux CI fails the experimental bank fixture.
The older green 13-group run does not validate this new bank feature.
Checkpoint `31934fc` recovered authoritative diagnostic project/timing inputs.
Preserve the original SFL files' CRLF/non-UTF-8 bytes. This session changed compiler,
fixtures and documentation, not the cache source bytes or the live Pocket top.

| Area | Actual evidence |
|---|---|
| Replacement SFL compiler | Expanded from combinational subset to registers, memory, local controls, lexical scopes, switch, multiple-task stages, hierarchy linking and bounded generators; **experimental**, not a full compiler |
| P02 caches | Actual corrected SFL sources compile and pass 242 behavioral checks; reverting each existing suffix comparison makes the bench fail |
| Compiler validation | 15 groups pass locally; 14 pass on Linux and bank initialization fails; GTE hierarchy elaborates only with experimental bank flag |
| Reference equivalence | Fifteen combinational cases pass 4,000 vectors each; six sequential cases p17–p21/p28 pass 4,000 cycles each; p27 parallel memory is an explicit mismatch |
| Cache lint | Both generated caches pass Verilator 5.052 without warnings |
| P04 memory frontend | Isolated behavioral scoreboard already passed across multiple parameter sets; not integrated |
| Replacement framebuffer RAM/SRAM blocks | Written and previously simulated; interface/timing assumptions remain |
| Recovered dependencies | UART files and pinned MIRLO controller/PHY imported; APF fetch script exists |
| Complete Pocket build, fit, timing, hardware FPS | **Not achieved or measured** |

Read [POCKET_SFLC.md](POCKET_SFLC.md) for exact compiler coverage, commands,
assumptions and the next hard tasks. [POCKET_IMPLEMENTATION.md](POCKET_IMPLEMENTATION.md)
contains memory and earlier dependency evidence; historical sections there
contain superseded status statements and are labeled accordingly.

## Immediate next hard job: P00 semantic compatibility

The compiler now makes isolated cache validation possible without a proprietary
license. Do not spend the next session redoing the parser spike or claiming that
all sequential semantics have been recovered.

1. Resolve the author-documented SFL+ versus archived native discrepancies:
   parallel memory writes and wide reg_ws reset. The latter affects loader address
   comparisons in Pocket/core.sflp. Current sampled native matches do not settle it.
2. Reduce the Linux bank initialization failure and record exact tool versions;
   Q-L2-03 assigns independent evidence gathering, leaving the compiler to L3.
3. Broaden typed-expression/selector evidence and audit real hierarchy clients.
   Constant par/any/alt expansion is implemented; join remains unsupported.
4. Progress the [Pocket diagnostic milestone](POCKET_DIAGNOSTIC_PLAN.md).
   [Authoritative inputs](POCKET_DIAGNOSTIC_INPUTS.md) now exist; diagnostic RTL
   and simulation can start without Quartus. No such RTL existed at handoff.
5. Preserve frontend isolation and CPU/GPU stalls until platform/controller
   ownership, CDC and reset contracts are met.

Run current local evidence:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/tests/run_tests.py
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

- The pinned official APF QPF/QSF/SDC/PLL reference is recovered. It has not yet
  been integrated and fitted as our diagnostic or PS1 project; Quartus is missing.
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
