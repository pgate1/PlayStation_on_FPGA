# Experimental SFL compiler — 2026-10-12

The replacement compiler now generates **the actual `Cache_IR.sflp` and
`Cache_Texture.sflp` sources** and runs them in a bounded behavioral regression.
This unblocks isolated cache validation without the proprietary toolchain.
It does **not** yet build the console or qualify a Pocket bitstream. Small
sequential probes now have independent reference evidence; this is not
equivalence of the full core.

Compiler checkpoint **f983b03**: 15 groups pass locally with Icarus 13, but the
new bank fixture now also passes Linux CI after a static-task bench fix
(run 38296978627); compiler memory logic was unchanged. Six
sequential native comparisons pass; parallel-memory p27 is a retained mismatch.
See the [current handoff](POCKET_HANDOFF_2026-10-12.md) for exact runs and commands.

## Implemented boundary

`tools/sflc/sflc.py` emits SystemVerilog (`iverilog -g2012`). It supports:

- Existing left-to-right combinational expressions and guarded AND/OR selection.
- Resettable, set-on-reset, explicitly initialized and resetless registers;
  synchronous assignments, increments/decrements and supported compound operators.
- Local instruction input/output/self terminals, explicit or combined argument
  declarations, invocation argument wiring and `instruct` guards.
- Statically sized memory with one selected physical write port, registered or
  combinational reads as specified by the source, and optional initialization.
- Lexically distinct local wires/registers, declaration after use, `switch`,
  `any`, `alt` with or without `else`, and oracle-tested data selector simplification.
  Inactive data is not universally zero; see the qualification below.
- Bounded compile-time `par/any/alt` generators with independent iteration locals.
  Bounds are nonnegative, start-inclusive/end-exclusive, limited to 4096 cumulative
  iterations per circuit. A bounded `join` with one assignment and one direct
  self-reference lowers to one binary reduction expression; accumulator on the
  right preserves ascending term order, while accumulator on the left reverses it.
  This matches both concrete expansions in the author's [SFL+ examples](https://pgate1.at-ninja.jp/memo/SFLP/).
  Other join shapes, empty joins and runtime bounds remain unsupported.
  Constant-indexed instance arrays (`ch[i]` inside a generator) resolve to a
  declared `ch_XX` (uppercase hex; digit count taken from the declared names, the
  element must exist, mixed digit counts are an error). The naming rule is inferred
  from the DSP/PlayStation_core declarations, not from a native oracle. A member-
  qualified `bus[i].port` resolves as an instance even if `bus` is also a selector;
  bare `bus[i]` retains normal signal/memory indexing.
- String constants (`"SCEI"`: 8 bits per character, first character most
  significant) and empty calls of a local argument-carrying `instrout`
  (activation only). See [core translation](POCKET_CORE_TRANSLATION.md): the
  full `PlayStation_core` now translates and elaborates from patched copies.
- Single- and multiple-task stages, captured register arguments, common actions,
  state guards, `goto` and `finish`.
- Header/interface linking, lexical instances, child control calls, child output
  event guards and call-result expressions. `--hierarchy` emits source-backed
  dependencies once; external Verilog leaves must be supplied separately.
- Constant width arithmetic, slicing expression results through sized temporary
  wires, bit reversal and sign extension including constants and expressions.

The language author's [SFL+ notes](https://pgate1.at-ninja.jp/memo/SFLP/)
provide source semantics for join ordering, register reset variants, parallel assignments,
local instruction arguments, lexical locals, memory initialization and stages.
The old [sfl2vl probe artifacts](POCKET_P00_TOOLCHAIN.md) remain the independent
oracle for the already-tested combinational subset. The implementation and
scoreboards here are newly written; licensed generated reference files are not
included in this repository.

Scopes are resolved before generating hardware. Registers preserve their values
when no assignment is enabled. A `reg` without an initializer has no synthesized
reset. Current `reg_ws` resets to numeric **1**, matching archived native p17.
However, the author's SFL+ notes specify all ones for a wide `reg_ws`. This is an
unresolved version/preprocessor compatibility gap, not proof the author's behavior
is wrong. `Pocket/core.sflp:473` uses wide `reg_ws` for loader address comparisons;
resolve this before integration. Memory initialization happens once, not on `p_reset`. Multiple guarded
writers select the address and data together, avoiding accidental multiport RAM
from separate procedural assignments. No synthesis evidence yet proves BRAM
inference or area savings.

`--assertions` adds simulation-only failures for simultaneous data/register
writers and multiple memory writers.
Control terminal invocations may OR their activation conditions. Assertions
check exercised traffic; they are not a static proof of mutually exclusive
writers. Some valid SFL programs intentionally OR simultaneous writers; run
reference equivalence without these optional exclusivity assertions.

## Experimental parallel banks

Two distinct constant write addresses in one memory require `--register-banks`
(or `translate(..., register_banks=True)`). The conservative check does not prove
guard exclusivity. Banks are limited to 256 words; each word receives guarded-OR
writes. Dynamic-only multiple writers retain the previous selected-port lowering.
RAM inference has not been qualified.

Since Q-L1-13 the per-word function is unchanged but dynamic-index writers of a
bank are routed through shared selected ports (`__sfl_wport_<mem>_<k>_{en,a,d}`):
writers with the same address expression share a port, and so do groups whose
guards are syntactically proven exclusive (same expression compared with
different constants, or a condition and its negation, after expanding local
control terminals). Unproven pairs keep separate ports, so simultaneous writes
to distinct words through different ports still all land (R3000A EX/MEM
write-back relies on this). Constant-zero writers only extend the enable, and
writers of one identical value are merged under an OR of their guards. Test 19
(`tests/bank_ports.sflp`, independent per-word model, two failing mutations) and
old-versus-new random co-simulation of the real bank modules cover this; see
[area audit](POCKET_SFLC_AREA.md).

The local independent scoreboard passes 6065 checks over 2019 cycles, but this
mode **does not match archived native 2010 p27**: native emits a priority chain
rather than updating all selected words. The optional comparison exits 1 at
post_edge cycle 4, q0=00 versus 9b. It is deliberately excluded from default
reference cases and retained as an explicit counterexample, not masked.

The earlier Linux failure (q0–q3 unknown at 2 ns) is resolved by static tasks in
the nonrecursive scoreboard. Icarus 11 saw initialized internal words but unknown
outputs with the old automatic-task bench. Compiler memory logic and all assertions
remain unchanged. See [reduction evidence](POCKET_BANK_INIT_REPRO.md).
The native mismatch still makes this flag unsuitable for live integration.

## Sequential reference evidence and data/control qualification

Latest downloaded oracle run `38250146942` contains native p17–p21 and p28. With
`cosim_sequential.py`, all six default cases pass 4,000 random cycles each
(seed 1), comparing every output around manually driven clock/reset edges.
Inputs include overlapping starts, simultaneous finish/generate and periodic
asynchronous reset. p28 compares generated control/local-counter behavior against
a small hand-expanded native fixture; it does not recover the missing SFL+
preprocessor itself. The references remain external.

Stages capture arguments on every generate, even while already active. Generate
wins over same-edge finish. State is initialized on reset and changed by `goto`;
it is retained across finish/restart. Tasks in one stage have independent sticky
active bits: starting a second task does not cancel the first. Finish clears all
tasks except those generated on that same edge. Shared argument writers combine
by guarded OR, as do ordinary SFL multiple writers. Nested stages are unsupported.

The p18 inactive argument mismatch is fixed. Further native probes p23–p26
establish that this applies to ordinary data selectors as well as call arguments:
a single distinct data value is continuously connected; identical repeated
values need no selector; an unconditional writer makes the tested data values
combine without their activation guards. Distinct conditional values retain
selection guards, including shared formals across different control terminals.
A one-bit literal assignment remains a Boolean control equation: `if(c) flag=1`
produces `flag=c`, whereas `if(c) data=bit_input` continuously connects the data.
Instruction activation and register enables remain guarded.

This reproduces the sampled archived **`-O2` output**, not a complete language or
optimizer specification. The compiler recognizes syntactically identical emitted
values and literal Boolean constants. Symbolically equivalent expressions,
constant folding beyond those literals and more complex selector transformations
remain unqualified. Do not rely on unspecified inactive data to indicate validity;
use the appropriate control terminal. Local scoreboards were corrected to remove
the earlier universal inactive-zero assumption, and a 4,096-case fixture now
covers p18/p23–p26 without needing external licensed references.

The old p13 stage probe produced no oracle because of invalid native syntax.
The new probes are small native inputs below the evaluation limit. Do not compact
or split real modules to evade the archived compiler's 500-line limit.

## Hierarchy boundary

A missing generated `foo.h` is derived only from the exact sibling `foo.sflp`'s
public declarations. Explicit headers are parsed recursively with cycle checks;
conflicting interfaces, bad port directions/arity, missing members and recursive
module instantiation fail. `declare ... interface` leaves omit implicit clocks;
ordinary declared/source-backed modules receive `p_reset` and `m_clock`.

The two-clocked-child plus combinational-leaf fixture passes 2,000 cycles,
covering activation guards, captured data, child events, local call results and
reset. ADSR and drawFillRect additionally elaborate with their real Verilog leaves.
The GTE hierarchy now elaborates with `--hierarchy --register-banks` plus real
mul_s16/mul_s32/mul_u32 Verilog leaves. gte_DIVIDE translates without that flag.
This is not GTE arithmetic proof. R3000A now stops at undeclared cache_hit_reg.
This does not prove full CPU/GPU hierarchy support. Header macros shared across
files, runtime-indexed instance arrays and identifiers colliding with SystemVerilog
keywords are not qualified; the last may currently fail downstream (a fixture
instance named `cell` did).

## Reproduce local evidence

From the project root, with Python 3, Icarus and vvp on PATH:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/tests/run_tests.py
```

Executed successfully with Python 3.12 and Icarus 13.0. Fifteen test groups pass locally and now on Linux after the bench-only fix:

| Evidence | Result and scope |
|---|---|
| Parser | Existing source corpus still parses; no SFL source bytes changed by this work |
| Sequential scoreboard | 4,000 cycles: reset variants, holds, parallel register updates, memory initialization/read-before-write, local register independence, task arguments, stalls, completion, repeated starts and reset interruption |
| Numeric scoreboard | 65,536 input pairs: carry, truncation, reversal, sign extension, negation, shifts, priority selection and inactive zero |
| Actual generated caches | 242 checks: all suffix offsets/words, data alignment, multiple indices including IR index 255, tag replacement, explicit IR clear, texture startup clear, response waits, hits/misses and reset during an outstanding texture miss |
| Cache mutations | Reverting the word-2 offset comparison in each temporary source copy causes the expected behavioral failure |
| Error handling | Invalid assignments, undeclared signals, invalid widths/slices/cases/tasks, unsupported constructs and exercised conflicting writers are rejected |
| Lexical scope | Sibling locals with identical spelling are independent; forward local declarations resolve |
| Elaboration only | 19 real leaf modules and supported `p*` probes; p08 join/sliced assignment remains unsupported; p27 needs the bank flag |
| Linked modules | 2,000 cycles with clocked children, an external leaf, events and guarded call results; invalid interfaces and cycles rejected |
| Multiple stage tasks | 40 directed checks including shared argument OR, sticky overlap, finish/generate and reset |
| Data/control selectors | 4,096 input/control cases covering sole/shared/repeated values, direct writers, one-bit literal controls and nested guards |
| Generators/banks | 6065 checks, 2019 cycles locally and on Linux; default bank rejection checked |
| GTE | Linked hierarchy elaborates under experimental bank flag; no arithmetic/fit proof |

The texture bench supplies responses only after the request has crossed an
accepting clock edge. It does not establish compatibility with a same-cycle ack
or with the missing legacy SDRAM controller. Cache bypass mode, concurrent
read/clear/refill, every address, and full-system memory ordering are not covered.
The test runner uses temporary directories, bounded subprocess timeouts, and
nonzero exit codes on failure. Mutations never edit the original cache files.

For optional comparison against the archived reference output directory:

```sh
python3 tools/sflc/cosim.py --reference-dir /path/to/sfl2vl-probe-out
```

Executed with seed 1 and 4,000 vectors each: **all fifteen pass** (`p01`, `p03`,
`p04`, `p09`, `p11`, `p12`, `p14`, `p15`, `p16`, p22–p26, and real `bsr_s16`). `p11` has no data
inputs, so it is a repeated constant-output check. The runner generates vectors
in Python, checks output widths, supports arbitrary input widths, and fails on
missing references, simulator failures, mismatches or missing PASS markers.
Earlier combinational references are external artifacts from Linux run `38215563441`; p22 uses
native subtraction instead of the unary-minus spelling rejected by the oracle.
That combinational suite was not rerun during the generator continuation. For the
six default sequential cases, use references from run `38250146942`:

```sh
python3 tools/sflc/cosim_sequential.py --reference-dir /path/to/sfl2vl-probe-out
```

The six default cases pass at seed 1, 4,000 cycles each, including overlapping
control inputs. No output masking is used to hide inactive-data mismatches.

Both caches also passed **Verilator 5.052 lint without warnings**:

```sh
python3 tools/sflc/sflc.py --assertions Cache_IR.sflp > /tmp/Cache_IR.sv
python3 tools/sflc/sflc.py --assertions Cache_Texture.sflp > /tmp/Cache_Texture.sv
verilator --lint-only --top-module Cache_IR /tmp/Cache_IR.sv
verilator --lint-only --top-module Cache_Texture /tmp/Cache_Texture.sv
```

`.github/workflows/sflc.yml` adds the local regression to CI without downloading
the proprietary compiler. The **earlier** 13-group selector snapshot passed Linux CI in run
[38222767443](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38222767443)
on isolated branch `sfl-oracle-20261012`, commit `c2da886`. This includes the final
selector implementation and fixture corrections. The matching native oracle
workflow [38222767521](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38222767521)
also completed; individual probe exits must still be inspected because that
workflow deliberately retains failures. Local reference comparisons used the
same p17–p26 sources from previously downloaded run `38215563441`.

Historical failing 15-group Linux run [38250146881](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38250146881)
failed the bank fixture; 14 groups passed. Its compiler/test snapshot `3c14120`
matches f983b03. The ineffective initialization experiment `8ad1d22` also failed
in [38250348469](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38250348469).
The unchanged assertions now pass in [38296978627](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38296978627)
with the static-task bench fix (snapshot 9ccdab6); all 15 groups are green.

## Next hard work, in order

1. **L3: SFL+ versus archived SFL contract.** Resolve parallel-memory and wide
   reg_ws discrepancies with the author's documented behavior. Recover the missing
   preprocessor lowering or explicitly qualify separate versioned semantics.
2. **Linux bench portability is fixed.** Read POCKET_BANK_INIT_REPRO.md rather
   than repeating Q-L2-03; no compiler semantic change was made.
3. **L3: typed expressions and selectors.** Broaden symbolic equivalence, decimal
   sizing, mixed widths, overflow before slicing and sign-extension contexts.
4. **L3: hierarchy and remaining constructs.** Audit real clients, join ordering,
   instance arrays, strings/buses and interface errors. Do not introduce implicit
   wires to silence source defects.
5. **L3: platform/controller integration.** Pinned diagnostic inputs now exist;
   Quartus, wrapper/CDC review, fitting and hardware acceptance remain open.

`DMA_CDR.sflp` currently fails on undeclared `dbg32` and `DMA_SPU.sflp` on
undeclared `size_mul` under default defines. Determine intended build defines
and original source intent before changing them; do not create implicit wires.
`drawRect.sflp` additionally references undeclared `under640`;
`PlayStation_core.sflp` declares `file_adrs` twice. These remain explicit errors.

Smaller independent packets live in [POCKET_MODEL_HANDOFF.md](POCKET_MODEL_HANDOFF.md).
P00 remains open. P02 has actual-source behavioral and mutation evidence under
this experimental compiler, but original-toolchain equivalence, synthesis and
hardware acceptance remain open. No bandwidth, game speed or FPS claim follows
from any result here.
