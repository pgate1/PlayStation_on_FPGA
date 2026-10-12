# Handoff — 2026-10-12, bounded generator checkpoint

Latest **compiler checkpoint: `f983b03`** on `pocket-work`. This document supersedes
the earlier continuation record. Read [compiler limits](POCKET_SFLC.md),
[diagnostic inputs](POCKET_DIAGNOSTIC_INPUTS.md), and the
[cross-provider queue](POCKET_MODEL_HANDOFF.md) before starting.
The user requested winding down near 15% of the five-hour allowance; the last
reported percentage before documentation was 18%. The agent cannot observe
that quota directly. No automatic five-hour resume has been scheduled.

## Outcome and commits

Target: original PS1 games on Analogue Pocket at correct guest speed, video first,
roughly 30 newly rendered frames/s in selected simple games, sound later.
**No new loadable Pocket bitstream, full-core build, fit/timing result, game boot,
or hardware FPS improvement exists from this work.**

- `6fbe8bc`: experimental compiler/cache milestone.
- `95d42dd`: another agent's portable component regressions/evidence.
- `0422745`: hierarchy linking, independent stage tasks and reference runner.
- `d93175d`: native data-selector corrections and p24–p26 tests.
- `e92456c`: commits the probe matrix, including p23–p26; its recorded statuses
  still need reconciliation. Do not omit this checkpoint.
- `9e1db93`: repairs the earlier handoff's missing e92456c history.
- `31934fc`: recovers pinned official Pocket timing/project inputs and unblocks
  the diagnostic RTL/simulation packet.
- **`f983b03`: bounded `par/any/alt` generators; independent lexical locals;
  p28 native comparison; explicit experimental register-bank flag; GTE hierarchy
  elaboration; retained p27 mismatch and Linux regression.**

Primary-branch commits above have not been pushed by this session. Only the
isolated `sfl-oracle-20261012` validation branch was pushed to
`https://github.com/ollisulopuisto/PlayStation_on_FPGA.git`. No PR or merge exists.
The documentation commit following f983b03 is discoverable using
`git log -1 --oneline -- docs/POCKET_HANDOFF_2026-10-12.md`; f983b03 denotes the
compiler content, not an assertion that no later documentation commit exists.

## Current compiler boundary

Existing linking, cache, stage and data-selector behavior remains. Generators
require nonnegative compile-time bounds and `i++`, use a start-inclusive,
end-exclusive range, and permit at most 4096 cumulative iterations per circuit.
Each `par` iteration has separate lexical locals. `any` combines enabled arms;
`alt` retains iteration/arm order. There is one final else outside the index
scope. Empty ranges are supported; runtime bounds and `join` still fail.

Memories with two distinct static write addresses are conservatively rejected
by default, even if their guards might be exclusive. `--register-banks` opts
into per-word guarded-OR writes for banks of at most 256 words. Same-address
writers OR their data; different words can update together. This mode is
**experimental, not native-equivalent and not hardware-qualified**. It has a
known Linux simulation failure described below. Dynamic-only multiwrite
patterns still use the previous selected-port lowering; they are not newly
qualified as parallel banks. No area/BRAM inference claim is established.

`GeometryTransformationEngine.sflp` plus linked gte_LIMIT/gte_DIVIDE and real
mul_s16/mul_s32/mul_u32 Verilog leaves now elaborates under the bank flag.
That is syntax/connectivity evidence only, not GTE arithmetic correctness.
`gte_DIVIDE.sflp` translates without the bank flag. CPU now reaches an explicit
undeclared `cache_hit_reg` error instead of stopping at generator syntax.

## Validation, including failures

Use `PYTHONDONTWRITEBYTECODE=1`: an old parser pyc is tracked. Python 3.12,
Icarus 13.0 and Verilator 5.052 were available locally; Quartus was not on PATH.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/tests/run_tests.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/tests/run_cache_boundaries.py
gh run download 38250146942 --repo ollisulopuisto/PlayStation_on_FPGA \
  --name sfl2vl-probe-out --dir /tmp/psx-oracle-38250146942
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/cosim_sequential.py \
  --reference-dir /tmp/psx-oracle-38250146942
# Expected failure: retained counterexample, not part of the default cases.
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/cosim_sequential.py \
  --reference-dir /tmp/psx-oracle-38250146942 --cases p27_parallel_memory
```

| Check | Exact outcome |
|---|---|
| Local current regression | **15 groups PASS**, including generator/bank scoreboard 6065 checks over 2019 cycles and GTE hierarchy elaboration |
| Earlier retained local coverage | 4000 sequential cycles, 65536 numerical pairs, 242 actual-cache checks, both reverted-cache mutations detected, 19 leaves elaborate, linked fixture 2000 cycles, 40 stage checks, 4096 selector cases |
| Current sequential native comparison | **Six cases PASS**, p17–p21 plus p28, 4000 cycles each, seed 1, all outputs around edges; p28 compares a generator fixture to a tiny hand-expanded native input |
| Parallel-memory native comparison | **FAIL as expected**, p27 post_edge cycle 4, q0 reference=00 DUT=9b, exit 1 |
| Earlier combinational native evidence | 15 cases PASS, 4000 vectors each, seed 1, references from run 38215563441; not rerun during this generator continuation |
| Earlier standalone boundaries/lint | 11 cache boundary checks PASS; both generated caches lint clean; not rerun during this continuation |
| Current Linux regression | **FAIL**, [38250146881](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38250146881), snapshot `3c14120` matching f983b03 compiler/test files; 14 groups pass, bank fixture fails initial q0–q3=xx at 2 ns |
| Attempted Linux initialization fix | Explicit constant initialization also **FAIL**, [38250348469](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38250348469), isolated snapshot `8ad1d22`; ineffective patch reverted on primary branch |
| Last completely green Linux checkpoint | 13-group selector snapshot `c2da886`, [38222767443](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38222767443) |
| Native oracle generation | [38250146942](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38250146942) succeeds; p28 individual log exit=0; external references downloaded locally |

The native workflow retains per-probe failures without failing its overall job;
inspect individual logs and generated files. Licensed reference output is not
vendored. The archived evaluation compiler has a 500-line limit: use tiny
independent semantic probes, never compact or split real sources to evade it.
Temporary oracle checkout: `/tmp/psx-sfl-oracle-pxkregzq`. Its extra branch trigger
is validation-only; do not copy that workflow change into the main branch.

## Hardest remaining issues, in order

1. **Resolve the SFL+ versus archived SFL semantic boundary.** Native 2010 p27
   lowers the writes to one source-priority chain (wr, then cell3, cell2, cell1,
   cell0), whereas the experimental bank mode writes all selected words.
   The author's [SFL+ notes](https://pgate1.at-ninja.jp/memo/SFLP/) describe parallel
   memory updates and a separate SFL+ preprocessor. A hand-expanded native probe
   is not proof of that missing preprocessor's output. Recover the real lowering
   or establish an explicit versioned semantic contract before integration.
2. **Wide reg_ws is an unresolved compatibility gap.** The same author document
   shows a four-bit reg_ws resetting to all ones; archived native p17 resets it
   to numeric 1. Current sflc follows p17. Earlier docs calling all-ones simply
   wrong were overbroad. `Pocket/core.sflp:473` uses reg_ws file_adrs<18> and
   sram_adrs<11> in address comparisons: the difference can affect loader behavior.
   Do not silently change it or claim SFL+ equivalence; preserve both references.
3. **Linux bank initialization failure.** Reduce the emitted unpacked-array
   initialization and constant read outputs on the CI simulator, record exact
   simulator version, and compare against local Icarus 13. Both dynamic-loop and
   explicit-word initialization failed. A simulator-version cause is only a
   hypothesis. Keep the failing initial-state assertion; do not mask X outputs.
4. Broaden typed-expression/selector evidence before trusting CPU/GTE arithmetic;
   symbolic selector folding, overflow/slicing and mixed widths remain partial.
   `join` ordering, instance arrays, strings/buses, nested stages and cross-header
   macro propagation remain unsupported or unqualified.

First errors under default defines:

| Source | Current result |
|---|---|
| R3000A.sflp | undeclared cache_hit_reg |
| GeometryTransformationEngine.sflp | default rejects parallel d writes; bank flag permits hierarchy elaboration |
| gte_DIVIDE.sflp | translates, including alt generator |
| GraphicProcessingUnit.sflp | unknown port poly.texture_full |
| PlayStation_core.sflp | duplicate interface port file_adrs |
| drawRect.sflp | undeclared under640 |
| DMA_CDR.sflp | undeclared dbg32 |
| DMA_SPU.sflp | undeclared size_mul |

## Other providers and next inexpensive tasks

Two read-only internal reviews checked other providers' work during wind-down.
No external provider was contacted. Use the precise copyable queue in
[POCKET_MODEL_HANDOFF.md](POCKET_MODEL_HANDOFF.md):

- Q-L1-03: refresh the matrix against **f983b03**; include p27's default rejection
  and opt-in mismatch separately, p28 PASS, and Linux FAIL. The 32-row e92456c
  matrix is now stale; schema success alone is not evidence of current outcomes.
- Q-L1-04: source inventory exists locally and was reviewed; owner should commit
  it rather than assigning duplicate research.
- Q-L1-05: done locally. `Pocket/diagnostic/check_inputs.py` exits 2 with the
  pinned QPF/QSF, timing reference and 13 APF hashes present; only `quartus_sh`
  is blocked (gates fitting, not RTL/simulation).
- Q-L2-02: diagnostic RTL/bench is ready, no Quartus required for simulation.
  No diagnostic_core.sv or tb_diagnostic_core.sv existed at this review.
- Q-L2-03: produce the minimal Linux initialization reproduction, own new repro
  files only; leave the compiler and assertions unchanged until reviewed.

Other providers' uncommitted work was preserved: Pocket/core.sflp UART include,
RAM/SRAM replacements and benches, hdl/, tools/apf/, .claude/, build manifest and
checkers, docs/POCKET_SOURCE_DEFECTS.md and Pocket/diagnostic/ preflight files.
Stage exact owned files; do not discard their work. Original SFL sources use
CRLF/non-UTF-8 bytes. No original core/cache source bytes were changed here.

## Pocket-visible path

Pinned full official core-template revision
`da3a021b1eaf742604d86d8dc9b33a6666263e6a` is cached under
`Pocket/build/reference/`. Matching QPF/QSF, pins, PLL and timing source exist.
The diagnostic contract fixes 12,287,999 Hz, total 400x512, active 320x240 and
register/phase details. This is an APF reference project, not a fitted PS1 project.
Quartus/device installation, wrapper/CDC integration, fit/timing, packaging and
physical Pocket test remain. An x86-64 Linux machine or appropriately provisioned
GitHub Actions runner can host Quartus; no installation was performed here.

Earlier diagnostic estimate was 1–3 focused workdays after build prerequisites;
that remains a planning range, not a promised delivery date. Gameplay improvements
remain unestimated pending full compilation and fit. Keep the memory frontend
isolated and CPU/GPU drawing stalls in place until ownership/CDC/reset contracts
and actual platform timing are established.
