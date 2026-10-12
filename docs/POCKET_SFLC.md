# Experimental SFL compiler — 2026-10-12

The replacement compiler now generates **the actual `Cache_IR.sflp` and
`Cache_Texture.sflp` sources** and runs them in a bounded behavioral regression.
This unblocks isolated cache validation without the proprietary toolchain.
It does **not** yet build the console or qualify a Pocket bitstream. Small
sequential probes now have independent reference evidence; this is not
equivalence of the full core.

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
  `any`, `alt` with or without `else`, and implicit zero on inactive selectors.
- Single- and multiple-task stages, captured register arguments, common actions,
  state guards, `goto` and `finish`.
- Header/interface linking, lexical instances, child control calls, child output
  event guards and call-result expressions. `--hierarchy` emits source-backed
  dependencies once; external Verilog leaves must be supplied separately.
- Constant width arithmetic, slicing expression results through sized temporary
  wires, bit reversal and sign extension including constants and expressions.

The language author's [SFL+ notes](https://pgate1.at-ninja.jp/memo/SFLP/)
provide the source semantics for register reset variants, parallel assignments,
local instruction arguments, lexical locals, memory initialization and stages.
The old [sfl2vl probe artifacts](POCKET_P00_TOOLCHAIN.md) remain the independent
oracle for the already-tested combinational subset. The implementation and
scoreboards here are newly written; licensed generated reference files are not
included in this repository.

Scopes are resolved before generating hardware. Registers preserve their values
when no assignment is enabled. A `reg` without an initializer has no synthesized
reset. `reg_ws` resets to numeric **1**, including wider registers (the earlier
all-ones implementation was corrected against p17). Memory initialization happens once, not on `p_reset`. Multiple guarded
writers select the address and data together, avoiding accidental multiport RAM
from separate procedural assignments. No synthesis evidence yet proves BRAM
inference or area savings.

`--assertions` adds simulation-only failures for simultaneous data/register
writers and multiple memory writers.
Control terminal invocations may OR their activation conditions. Assertions
check exercised traffic; they are not a static proof of mutually exclusive
writers. Some valid SFL programs intentionally OR simultaneous writers; run
reference equivalence without these optional exclusivity assertions.

## Sequential reference evidence and open mismatch

Linux oracle run `38184207585` generated native p17–p21 successfully. With the
new `cosim_sequential.py`, p17, p19, p20 and p21 pass 4,000 random cycles each
(seed 1), comparing every output around manually driven clock/reset edges.
Inputs include overlapping starts, simultaneous finish/generate and periodic
asynchronous reset. The references remain external.

Stages capture arguments on every generate, even while already active. Generate
wins over same-edge finish. State is initialized on reset and changed by `goto`;
it is retained across finish/restart. Tasks in one stage have independent sticky
active bits: starting a second task does not cancel the first. Finish clears all
tasks except those generated on that same edge. Shared argument writers combine
by guarded OR, as do ordinary SFL multiple writers. Nested stages are unsupported.

**Open mismatch: p18 instruction arguments.** The oracle drives a sole call's
argument unconditionally, even while its control is inactive. The current
compiler guards it. Native p23 distinguishes single/multiple call sites and a
mixed direct writer; await that reference before generalizing a fix. Do not
claim instruction-argument equivalence or use this compiler for live integration.

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
This does not prove full CPU/GPU hierarchy support. Header macros shared across
files, instance arrays and identifiers colliding with SystemVerilog keywords are
not qualified; the last may currently fail during downstream elaboration.

## Reproduce local evidence

From the project root, with Python 3, Icarus and vvp on PATH:

```sh
python3 tools/sflc/tests/run_tests.py
```

Executed successfully with Python 3.12 and Icarus 13.0. Twelve test groups pass:

| Evidence | Result and scope |
|---|---|
| Parser | Existing source corpus still parses; no SFL source bytes changed by this work |
| Sequential scoreboard | 4,000 cycles: reset variants, holds, parallel register updates, memory initialization/read-before-write, local register independence, task arguments, stalls, completion, repeated starts and reset interruption |
| Numeric scoreboard | 65,536 input pairs: carry, truncation, reversal, sign extension, negation, shifts, priority selection and inactive zero |
| Actual generated caches | 242 checks: all suffix offsets/words, data alignment, multiple indices including IR index 255, tag replacement, explicit IR clear, texture startup clear, response waits, hits/misses and reset during an outstanding texture miss |
| Cache mutations | Reverting the word-2 offset comparison in each temporary source copy causes the expected behavioral failure |
| Error handling | Invalid assignments, undeclared signals, invalid widths/slices/cases/tasks, unsupported constructs and exercised conflicting writers are rejected |
| Lexical scope | Sibling locals with identical spelling are independent; forward local declarations resolve |
| Elaboration only | 19 real leaf modules and supported `p*` probes; p08 generators fail explicitly |
| Linked modules | 2,000 cycles with clocked children, an external leaf, events and guarded call results; invalid interfaces and cycles rejected |
| Multiple stage tasks | 40 directed checks including shared argument OR, sticky overlap, finish/generate and reset |

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

Executed with seed 1 and 4,000 vectors each: **all eleven pass** (`p01`, `p03`,
`p04`, `p09`, `p11`, `p12`, `p14`, `p15`, `p16`, `p22`, and real `bsr_s16`). `p11` has no data
inputs, so it is a repeated constant-output check. The runner generates vectors
in Python, checks output widths, supports arbitrary input widths, and fails on
missing references, simulator failures, mismatches or missing PASS markers.
Latest references are external artifacts from Linux run `38212896810`; p22 uses
native subtraction instead of the unary-minus spelling rejected by the oracle.
This is combinational equivalence only. For the currently passing sequential cases:

```sh
python3 tools/sflc/cosim_sequential.py --reference-dir /path/to/sfl2vl-probe-out \
  --cases p17_registers p19_stage p20_retained_stage p21_multi_task
```

The default five-case run currently exposes the p18 mismatch above.

Both caches also passed **Verilator 5.052 lint without warnings**:

```sh
python3 tools/sflc/sflc.py --assertions Cache_IR.sflp > /tmp/Cache_IR.sv
python3 tools/sflc/sflc.py --assertions Cache_Texture.sflp > /tmp/Cache_Texture.sv
verilator --lint-only --top-module Cache_IR /tmp/Cache_IR.sv
verilator --lint-only --top-module Cache_Texture /tmp/Cache_Texture.sv
```

`.github/workflows/sflc.yml` adds the local regression to CI without downloading
the proprietary compiler. The probe branch ran this workflow on Linux; its older compiler snapshot fails
the newly added multi-task probe. Current local changes have not yet had a green
remote run. The native oracle workflow succeeds, but that workflow deliberately
retains failed probe logs: inspect each individual exit status.

## Next hard work, in order

1. **L3: instruction-argument closure.** Resolve p18 using the native p23
   evidence, then rerun both independent reference suites and the local regression.
2. **L3: typed expression audit.** Broaden decimal sizing, mixed-width arithmetic,
   overflow before slicing and sign-extension contexts beyond p22. Do this before
   trusting GTE/CPU arithmetic.
3. **L3: hierarchy audit.** Exercise real clients now that linking works; establish
   remaining call side effects, lexical interfaces and error boundaries before
   enabling CPU/GPU integration.
4. **L3: constant generators and remaining constructs.** Implement compile-time
   `par/any/alt` expansion and separately establish `join` ordering. Preserve
   lexical instance/local names. String literals and `bus`/bidirectional
   semantics also remain unsupported. Unsupported input must keep failing.
5. **L3: platform/controller integration.** Return to P03/P04 once P00 can build
   the hierarchy. Do not infer safety from these isolated tests or remove stalls.

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
