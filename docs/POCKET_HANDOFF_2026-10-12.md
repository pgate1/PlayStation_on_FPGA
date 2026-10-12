# Handoff — 2026-10-12, compiler/linker checkpoint

This is the latest continuation record. Start here, then read
[POCKET_SFLC.md](POCKET_SFLC.md) and [POCKET_START_HERE.md](POCKET_START_HERE.md).
The user requested a handoff after this checkpoint; do not restart the parser
spike, repeat completed task packets, or assume a Pocket bitstream exists.

## Goal and present outcome

Target: original PS1 games on Analogue Pocket at correct guest speed, roughly
30 newly rendered frames/s in selected simple games, video first and sound later.
Current progress is build recovery and correctness evidence. **No loadable new
Pocket bitstream, full-core compile, fit/timing result, game boot, or hardware
FPS improvement has been achieved.**

The compiler now links modules and emits tested sequential behavior, enabling
isolated cache and hierarchy validation without the unavailable original SFL+
toolchain. Several incorrect initial assumptions were found with the native
compiler oracle and corrected, rather than hidden by the testbench.

## Checkpoints and ownership

- `6fbe8bc`: first experimental compiler/cache milestone, probes and regressions.
- `95d42dd`: another agent's portable HDL runner and evidence record. Read and
  preserved; five bounded component tests are recorded there.
- `0422745`: interface/hierarchy linking, multiple-task stages, sequential oracle
  runner, diagnostic plan and cross-provider task queue.
- The follow-up commit containing this handoff fixes native data selection and
  adds probes p24–p26 plus the 4,096-case selector fixture. Find its hash with
  `git log -1 --format=%h -- docs/POCKET_HANDOFF_2026-10-12.md`.

Primary branch is `pocket-work`. Its new checkpoint commits have **not** been
pushed by this session. The isolated validation branch `sfl-oracle-20261012`
**was** pushed to `https://github.com/ollisulopuisto/PlayStation_on_FPGA.git`.
Its final tested snapshot is `c2da886cd385559f9e8c3a7031bfc367e58a239b`.
It contains the matching compiler/tests/probes but is not a complete copy of
the primary branch's documentation/platform work. No PR or merge was created.

Other providers are working in this shared checkout. Check `git status` before
editing or committing and stage exact owned paths. Do not discard their work.
Original top-level `.sflp` files use CRLF/non-UTF-8 bytes; preserve them. This
session did not rewrite cache or console source bytes.

## Implemented and independently checked

**Linking:** explicit `%i` headers, inline interfaces, instance ports, guarded
control calls, child output-event guards, call-result expressions, lexical
instances, and `--hierarchy` dependency emission. Missing `foo.h` is derived only
from the exact sibling `foo.sflp` public declarations. External Verilog leaves
remain explicit build inputs. Bad directions/arity/ports, conflicting interfaces
and include/instantiation cycles fail. A 2,000-cycle linked fixture exercises
clocked children, a combinational leaf, captured arguments, responses and reset.

**Registers/stages:** `reg_ws` resets to numeric 1, including wider registers;
the earlier all-ones assumption was wrong. Stage state persists across
finish/restart unless changed by `goto`. Generate captures arguments even while
active and wins over simultaneous finish. Tasks within a stage have independent
sticky active bits; generating a second task does not cancel the first. Shared
argument and register writers use guarded OR, not source-order priority.

**Data/control distinction:** the native `-O2` compiler does not force every
inactive data output to zero. A sole distinct data value stays connected,
repeated identical values need no selector, and the tested unconditional-writer
cases OR their data continuously. Multiple distinct conditional values retain
their guards. One-bit literal assignments act as Boolean control equations;
one-bit variable data can remain continuously connected. Control terminal
activation and register enables remain guarded. Native p18/p23–p26 exposed these
differences; the implementation and old fixture assumptions were corrected.

This is a sampled oracle match, **not a complete specification of the native
optimizer**. `data_mux` currently recognizes syntactically identical emitted
values and literal Boolean constants. Symbolically equivalent expressions and
broader constant folding are unqualified. Keep this distinction in later work.
`--assertions` checks simultaneous writers and is deliberately stricter than
valid SFL programs that intentionally OR overlapping writers. Reference runners
disable those assertions and compare all outputs without inactivity masks.

## Exact evidence and reproduction

Local tools: Python 3.12, Icarus 13.0/VVP, Verilator 5.052. Quartus and native SFL
tools are not on PATH. Use `PYTHONDONTWRITEBYTECODE=1`: the repository still tracks
an old parser `.pyc`, and imports without this setting can dirty it.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/tests/run_tests.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/tests/run_cache_boundaries.py
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/cosim.py --reference-dir /tmp/psx-oracle-38215563441
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/cosim_sequential.py --reference-dir /tmp/psx-oracle-38215563441
```

Results at this checkpoint:

| Check | Evidence |
|---|---|
| Local main regression | 13 groups PASS: 4,000 sequential cycles; 65,536 numerical pairs; 242 actual-cache checks and detection of both reverted suffix-comparison mutations; 19 real leaf elaborations; linker errors/2,000 cycles; 40 multi-task checks; 4,096 selector cases |
| Standalone cache boundaries | 11 checks PASS, including single-word IR write, targeted/repeated clear, texture index 255 and long stall |
| Combinational native comparison | 15 cases PASS, 4,000 vectors each, seed 1: p01, p03, p04, p09, p11, p12, p14, p15, p16, p22–p26, real bsr_s16 |
| Sequential native comparison | All five p17–p21 PASS, 4,000 cycles each, seed 1; reset plus pre/post-edge outputs; overlapping inputs included |
| Verilator | Both generated caches pass lint without warnings after the selector fix |
| Linux regression | Final 13-group snapshot `c2da886` passes [run 38222767443](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38222767443) |
| Native oracle CI | Matching workflow [38222767521](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38222767521) succeeds; local comparisons used downloaded earlier run 38215563441 with the same probe inputs |

Reference Verilog is external, not vendored. If `/tmp` artifacts disappear,
download the known comparison artifact:

```sh
gh run download 38215563441 --repo ollisulopuisto/PlayStation_on_FPGA \
  --name sfl2vl-probe-out --dir /tmp/psx-oracle-38215563441
```

The native workflow deliberately captures failures without failing the overall
job. Inspect individual `.log` exit statuses and `.v` presence, not just its green
badge. Native p23 initially failed declaration ordering and was corrected;
p22 unary minus was rejected, so the native probe uses `0x00-a`. The unsupported
old p13 does not establish any stage behavior. Evaluation tool limit is 500
lines: use small semantic probes, never compact/split real modules to evade it.

Temporary isolated checkout: `/tmp/psx-sfl-oracle-pxkregzq`. Its workflow adds the
validation branch to the native probe trigger; do not inadvertently overwrite
the primary branch workflow with that temporary change. No tool process is
intentionally left running at handoff.

## Next hard work and concrete blockers

The compiler is frozen for this checkpoint so another provider can refresh the
result matrix. For the next L3 implementation, use an isolated branch and retain
all reference regressions. A high-value next feature is bounded compile-time
`par/any/alt` generator expansion, with native tiny probes and lexical-scope tests.
In parallel with that design, broaden typed expression/selector oracle coverage
before trusting CPU/GTE arithmetic. Do not silently accept unsupported forms.

Current first-error survey, default defines, using `sflc.translate`:

| Source | First result |
|---|---|
| `R3000A.sflp` | `NotImplementedError: par generator` |
| `GeometryTransformationEngine.sflp` | `NotImplementedError: par generator` (the filename is not `GTE.sflp`) |
| `gte_DIVIDE.sflp` | `NotImplementedError: alt generator` |
| `GraphicProcessingUnit.sflp` | `NameError: unknown port poly.texture_full`; call at line 567, missing from drawPoly public interface |
| `PlayStation_core.sflp` | `ValueError: duplicate interface port file_adrs` |
| `drawRect.sflp` | `NameError: undeclared under640` |
| `DMA_CDR.sflp` | `NameError: undeclared dbg32` |
| `DMA_SPU.sflp` | `NameError: undeclared size_mul` |
| `ADSR.sflp`, `drawFillRect.sflp`, `drawPoly.sflp` | Translate individually; this is not full hierarchy/behavioral proof |

ADSR and drawFillRect were additionally elaborated earlier with their real
Verilog leaves. Investigate source intent/defines before fixing these errors.
No implicit wires or duplicate-port suppression. Also unqualified/unsupported:
nested stages, `join`/relay ordering, strings, buses/bidirectional behavior,
instance arrays, cross-header macro propagation, and SFL identifiers colliding
with SystemVerilog keywords (these may currently fail downstream elaboration).

## Cross-provider tasks and remaining local work

Use the claim queue in [POCKET_MODEL_HANDOFF.md](POCKET_MODEL_HANDOFF.md).
Ready: Q-L1-03 result snapshot refresh; Q-L1-04 source-defect evidence inventory;
Q-L1-05 diagnostic input preflight. Q-L2-02 display/input RTL waits for
authoritative platform/timing inputs. Each has exact owned paths and acceptance.
No external provider was automatically contacted; these are copyable assignments.

Other agents' work was read and preserved. Current local-only, uncommitted
files include the RAM/SRAM replacements and benches, imported `hdl/`, APF fetch
tooling, modified `Pocket/core.sflp` UART include, `.claude/`, and the four
`tools/pocket/` manifest/matrix files. They were not bundled into the compiler
checkpoint. Review/commit them under their owners rather than treating them as
part of a clean checkout. The 79-entry build manifest checker passes. The probe
matrix checker **currently fails** on omitted p23–p26 rows; Q-L1-03 is explicitly
assigned that refresh. Its old p21 status also needs updating. A passing schema
checker would not by itself prove the recorded compilation results.

Keep the isolated memory frontend disconnected until request ownership, loader
CDC, common reset/flush, controller timing and platform clocks are resolved.
Do not remove CPU/GPU drawing stalls based on isolated simulation results.

## Pocket-visible milestone and ETA limits

[POCKET_DIAGNOSTIC_PLAN.md](POCKET_DIAGNOSTIC_PLAN.md) separates a test-pattern/
button-response milestone from PS1 gameplay. Cached APF files exist, but no
complete Pocket QPF/QSF, verified pins/video timing/PLL setup or working local
Quartus was established. The diagnostic planning range is **1–3 focused workdays
after those prerequisites exist**, not 1–3 days from this handoff. A game build
with visible gameplay improvements remains weeks rather than days, with low
confidence until full compilation and fit. None of the passing tests above
establishes a visual or frame-rate improvement on physical hardware.
