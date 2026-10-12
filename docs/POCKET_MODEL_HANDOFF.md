# Assigning the roadmap to other models

Check [rolling checkpoints](POCKET_CHECKPOINTS.md) for active claims and newer
results before taking a packet. **Q-L1-03 and Q-L2-02 are complete in `77b3f50`.**
Q-L2-03 is complete: Linux passes after the bench-only fix. Other models can start
[the autonomous ready packets](POCKET_READY_TASKS.md) without waiting for root.

**Resume work from [POCKET_START_HERE.md](POCKET_START_HERE.md).** It records what was actually completed, installed tools, unresolved blockers and the next implementation packet. The [memory contract](POCKET_MEMORY_CONTRACT.md) now has isolated RTL; see [implementation evidence](POCKET_IMPLEMENTATION.md). The isolated memory frontend has passed behavioral simulation. Full-system simulation and live integration remain outstanding.

Read [POCKET_ROADMAP.md](POCKET_ROADMAP.md) for the evidence, task contracts and dependency table, and [POCKET_BENCHMARKS.md](POCKET_BENCHMARKS.md) for acceptance. The goal is sound plus approximately 30 fps in selected original PS1 games at correct game speed.

## Spend model capacity where it matters

| Work packet | Model level | Suggested delegation |
|---|---|---|
| Dependency inventory, build manifest, artifact hashes, report tables and packaging metadata | L1 economical | Give exact file lists and schemas; strong model reviews outputs |
| Focused cache fix, counter tooling, trace conversion and individual GPU fixtures | L2 strong coder | Small patch plus failing-before/passing-after test evidence |
| Isolated I2S/PCM block, simple GPU primitive, controls or persistence tooling | L2 strong coder | Explicit interface contract; L3 reviews CDC, ordering and timing |
| Build/platform reconstruction, shared memory, loader CDC, authoritative VRAM migration | L3 strongest reasoning + RTL experience | Design first, staged implementation, synthesis/timing evidence |
| Shared SPU, CPU/GPU overlap, guest timing, GTE arithmetic refactoring, CD audio | L3 strongest reasoning + RTL experience | One subsystem at a time; independent verification plan before edits |
| Final integration, resource allocation and conflicting hardware behavior | L3 plus FPGA expert | One architecture owner; hardware qualification is mandatory |

Long context alone is insufficient. Prefer a model that can reason about nonblocking assignments, finite-width signed arithmetic, clock crossings, external RAM timing, FIFOs and synthesis resource inference. A cheaper model with proven HDL skills can outperform a larger model unfamiliar with those topics. The tiers are minimum supervision recommendations, not guarantees.

## Efficient dispatch order

1. Keep **P00** compiler control/sequential work with the strongest model. The L1 dependency manifest/checker is complete (79 entries); do not reassign it.
2. The portable regression/evidence packet and P02 cache boundary fixtures are complete. Use the ready-claim queue below for the next independent low-cost work; do not duplicate those outputs.
3. Have the architecture owner specify **P04** interfaces before assigning dependent blocks. Freeze request ownership, byte lanes, reset and completion semantics in a shared document.
4. Implement **P06** VRAM rendering/scanout and reclaim internal RAM. Reserve resources and bounded memory service for later audio; defer **P05/P07** implementation until the video gate passes.
5. Assign **P08/P09** to one owner or tightly coordinated sequential tasks; scheduling and game time are coupled. Assign **P10/P13** only with the pixel sink/cache contract in hand.
6. Implement required rendering/boot compatibility and run the **M4 video gate** through P16: approximately 30 fps, correct game speed, silent output permitted. Pull forward only the data-streaming part of **P11** if needed. Run **P12** earlier only if fresh fit data shows an area problem.
7. After M4, implement **P05/P07** and required CD audio from **P11**, then repeat **P16** for the combined M6 gate with sound enabled.

Use separate branches/checkouts for implementation packets. Two models should not independently change `PlayStation_core.sflp`, `GraphicProcessingUnit.sflp` or `Pocket/core_top.v` without an integrator. Commit interface changes before dependent branches start integrating.

## Cross-provider task queue

The tasks below are ready to claim by one provider at a time. They are provider-neutral prompts, not a claim that any external model has already been contacted or assigned. A provider claims one task ID before editing, owns only its listed paths, and leaves shared compiler sources alone. When a task is in progress, other providers should choose a different ID. Do not duplicate completed tasks.

| Task ID | Status | Minimum tier | Prerequisites | Owned paths |
|---|---|---|---|---|
| Q-L1-01 P00 dependency manifest | **Done locally, uncommitted** — 79 entries; checker passes | L1 | None | `tools/pocket/build_inputs.json`, `tools/pocket/check_build_inputs.py` (closed) |
| Q-L1-02 Portable regressions/evidence | **Done** — commit `95d42dd`; five bounded tests recorded | L1 | Icarus/VVP | `tools/pocket/run_regressions.sh`, `docs/POCKET_REGRESSION_EVIDENCE.md` (closed) |
| Q-L2-01 Cache boundary fixtures | **Done** — commit `6fbe8bc`; 11 checks | L2 | Experimental compiler and Icarus | `tools/sflc/tests/tb_cache_boundaries.sv`, `tools/sflc/tests/run_cache_boundaries.py` (closed) |
| Q-L1-03 P00 probe-result snapshot refresh | **Done — 77b3f50, 34 probes** | L1 | Use compiler checkpoint `f983b03`; p27 known mismatch and p28 comparison now exist | `tools/pocket/p00_probe_matrix.json` only |
| Q-L1-04 Read-only source-defect inventory | **Done locally, owner commit pending** | L1 | None; compiler diagnostics are optional evidence | Existing `docs/POCKET_SOURCE_DEFECTS.md` only; do not duplicate |
| Q-L1-05 Diagnostic input preflight | **Done locally, owner commit pending**; checker exits 2 (Quartus only) | L1 | Read access to cached APF inputs and fetch manifest | Existing `Pocket/diagnostic/inputs.json`, `Pocket/diagnostic/check_inputs.py` only |
| Q-L2-02 Diagnostic display/input core | **Done — 77b3f50, simulation/lint pass** | L2 | Pinned timing, interface and project sources in [diagnostic inputs](POCKET_DIAGNOSTIC_INPUTS.md); Quartus only gates fitting | New `Pocket/diagnostic/diagnostic_core.sv`, `Pocket/diagnostic/tb_diagnostic_core.sv` only |
| Q-L2-03 Linux bank initialization reproduction | **Done — static-task bench fix, Linux PASS** | L2 | f983b03 generated bank fixture; Linux Icarus access preferred | New `tools/sflc/tests/repro_bank_init.sv`, `docs/POCKET_BANK_INIT_REPRO.md` only |

### Archived assignment Q-L1-03 (completed) — refresh P00 result snapshot

**Copyable assignment:** use the frozen compiler checkpoint **f983b03**, with
outcomes recorded in `POCKET_HANDOFF_2026-10-12.md`. Own only
`tools/pocket/p00_probe_matrix.json`. Commit e92456c added p23–p26; the 32-row
matrix now lacks p27/p28 and has stale p21/oracle classifications. Record default
p27 rejection, opt-in bank comparison **FAIL** (cycle 4, q0 00/9b), and p28 native
comparison **PASS** separately. Do not turn successful native source translation
into an equivalence claim. Record 15 local regression groups PASS and current
Linux bank fixture FAIL, with commands/versions/run IDs. Refresh earlier statuses
only from their cited evidence. Do not alter the compiler, probes, checker or other
docs. Run `PYTHONDONTWRITEBYTECODE=1 python3 tools/pocket/check_p00_probes.py` and
`PYTHONDONTWRITEBYTECODE=1 python3 tools/sflc/tests/run_tests.py`; report actual exit
codes, including failures. If the schema cannot express separate outcomes, report
that limitation rather than mislabeling a row or expanding your file ownership.
Check that compiler sources still match f983b03 before writing.

### Completed locally Q-L1-04 — source-defect inventory

`docs/POCKET_SOURCE_DEFECTS.md` now exists from another provider and was read during
handoff. It records five source candidates under default and DEMO defines, without
source fixes. Its owner should review/commit that exact file; do not repeat this
packet or silently change original source bytes. A later L3 review should decide
intent and fixes. This completion status does not certify intended hardware behavior.

### Completed locally Q-L1-05 — diagnostic input preflight

Existing `Pocket/diagnostic/inputs.json` now records the pinned reference QPF/QSF,
the timing source (`core_top.v:519-524`, `mf_pllbase_0002.v:34,37`) and all 13 APF
hashes. `check_inputs.py` exits 2 with only `quartus_sh` blocked. The PS1-only IP
(`main_pll_0002`, `sdram128_burstn_ctrl_100`) is reported as missing but is not a
diagnostic requirement. Owner should verify and commit the two files. Temporary-copy
tests exit 1 for a hash mismatch and for a missing `timing_reference.pixel_clock_hz`.

### Archived assignment Q-L2-02 (completed) — diagnostic display/input core

**Copyable assignment:** use [POCKET_DIAGNOSTIC_INPUTS.md](POCKET_DIAGNOSTIC_INPUTS.md), which supplies the pinned primary reference, local cache, exact timing, hashes, pixel-domain interface and acceptance. Own only `Pocket/diagnostic/diagnostic_core.sv` and `Pocket/diagnostic/tb_diagnostic_core.sv`. The source prerequisite is now satisfied; start RTL and Icarus simulation without waiting for Quartus. L3 owns the APF wrapper, reset/CDC review, PLL, constraints and fitting. Report simulation evidence separately from the still-pending hardware gates.

### Claimed by root Q-L2-03 — reproduce Linux bank initialization

**Copyable assignment:** compiler checkpoint f983b03 passes the generator/bank
scoreboard locally under Icarus 13, but Ubuntu 22.04 run 38250146881 fails at 2 ns:
q0–q3 are X where initialized zero is expected. An explicit constant-index
initialization variant on isolated snapshot 8ad1d22/run 38250348469 failed too;
that speculative patch was reverted on primary. Own only new
`tools/sflc/tests/repro_bank_init.sv` and `docs/POCKET_BANK_INIT_REPRO.md`.

Reduce the exact emitted unpacked array, initial assignments, constant output
reads and per-word clocked writers. Compare variants with/without unrelated
resettable counters; print internal cells and outputs before the first clock.
Record exact Icarus/VVP versions, commands, generated-input hash, OS and results.
First reproduce the original failure before changing a construct. If only local
Icarus is available, supply the reproducer and mark Linux validation pending.
Do not infer a simulator bug solely from differing results, remove assertions,
mask X values, change compiler behavior, alter CI workflows or claim a fix.
Acceptance: the smallest evidence-backed failing case plus a clearly stated
hypothesis/next experiment. L3 owns the compiler fix and regression decisions.

## Current dispatch

The archived assignment text above records previous contracts, not ready tasks.
Use [POCKET_READY_TASKS.md](POCKET_READY_TASKS.md) for new work that can finish
independently. Root remains responsible for compiler semantics and APF integration;
smaller providers should not wait on those tasks to implement a ready packet.

## Provider completion/report protocol

For any claimed task, send the user/task owner the task ID and owned paths before editing. Keep changes restricted to those paths; never overlap the active compiler owner. Finish with: (1) paths changed, (2) exact commands and exit statuses, (3) evidence artifacts, (4) unresolved assumptions/blockers, and (5) the next dependency or status. Do not claim external dispatch, compiler freeze, hardware fit, visible output, or a passing check without the corresponding evidence. A task that is blocked should return the concrete missing prerequisite and leave its owned outputs unchanged where possible.

## Copyable implementation prompt

```text
Implement task Pxx from docs/POCKET_ROADMAP.md.
Read docs/POCKET_BENCHMARKS.md and the task's cited source files.
The target is Analogue Pocket 5CEBA4F23C8, sound and approximately
30 presented game frames/s at correct game speed in the selected scenes.
Current priority: video/30 fps first (M4), audio afterwards (M5/M6).
Respect that order and preserve measured resource headroom for audio.

First report:
- Which prerequisites are satisfied, with artifact paths.
- The interface/behavior changes and invariants you will preserve.
- Expected resource costs and how you will measure them.
- A focused validation plan and the files you will edit.

Then implement only this task in reviewable steps. Preserve source
encoding and do not hand-edit generated RTL as the authoritative source.
Use original PS1 binaries for acceptance; desktop ports are references.
Add/run the focused tests needed by the task contract when tools exist.
If a tool/dependency is missing, record exactly what prevents validation.
Do not invent successful builds, hardware results, throughput or FPS.

Return a handoff containing changed files, interface contracts, commands,
test outcomes, fit/timing deltas, unresolved failures, and the next task
whose prerequisites are now satisfied. Archive raw reports/traces.
```

## Reviewer checklist

- Does every claimed improvement have a before/after measurement of the same workload?
- Does the change fit in physical RAM blocks, DSPs and ALMs, with timing closed?
- Are request acceptance and completion distinct, with no broadcast ack ambiguity?
- Do resets/clock crossings handle the actual clock relationship rather than hiding paths with false-path constraints?
- Do resource savings preserve required numeric width, rounding, IRQ and cache semantics?
- Does audio remain correct under the maximum simultaneous rendering/streaming load?
- Are native game speed and true presentation cadence separate from output refresh and flip proxies?
- Are MIRLO64-derived blocks pinned and attributed, and their N64-specific assumptions removed?

A strong model should review architecture-sensitive work even when a small task was implemented by an economical model. A human must supply or operate the physical hardware and assess external timing evidence before the final result is called validated.
