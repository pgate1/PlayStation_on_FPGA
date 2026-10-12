# Assigning the roadmap to other models

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
| Q-L1-03 P00 probe-result snapshot refresh | **Partially done — reconcile evidence** | L1 | Use the committed handoff snapshot, matched by CI branch `c2da886`; p20–p26 probes are present | `tools/pocket/p00_probe_matrix.json` only |
| Q-L1-04 Read-only source-defect inventory | **Ready** | L1 | None; compiler diagnostics are optional evidence | New `docs/POCKET_SOURCE_DEFECTS.md` only |
| Q-L1-05 Diagnostic input preflight | **Ready** | L1 | Read access to cached APF inputs and fetch manifest | New `Pocket/diagnostic/inputs.json`, `Pocket/diagnostic/check_inputs.py` only |
| Q-L2-02 Diagnostic display/input core | **Ready for RTL/simulation** | L2 | Pinned timing, interface and project sources in [diagnostic inputs](POCKET_DIAGNOSTIC_INPUTS.md); Quartus only gates fitting | New `Pocket/diagnostic/diagnostic_core.sv`, `Pocket/diagnostic/tb_diagnostic_core.sv` only |

### Ready packet Q-L1-03 — refresh P00 result snapshot

**Copyable assignment:** the compiler is frozen for this handoff (see `POCKET_HANDOFF_2026-10-12.md`); use its committed snapshot and refresh only `tools/pocket/p00_probe_matrix.json` using the current probes and current tool availability. Commit `e92456c` adds p23–p26 and the checker passes all 32 rows. Correct the remaining stale p21 unsupported status and oracle not-run classifications against the handoff evidence. Include the new p20–p26 cases, distinguish local compiler/test evidence from archived sfl2vl oracle evidence, and retain exact commands, status, and concise diagnostics. Do not edit `tools/sflc/sflc.py`, `sflp_parse.py`, probe source, matrix checker, or other docs. Run `python3 tools/pocket/check_p00_probes.py` and `python3 tools/sflc/tests/run_tests.py`; report both exact outcomes. If the compiler is still changing, stop before writing and report the prerequisite as unmet.

### Ready packet Q-L1-04 — read-only source-defect inventory

**Copyable assignment:** inspect, but do not fix, these candidate source defects: missing `drawPoly.texture_full` port invoked by `GraphicProcessingUnit.sflp:567`; undeclared `under640` use in `drawRect.sflp:85,112`; `dbg32`/`dbg32_reg` assignment versus the `dbg`/`dbg_reg` declarations in `DMA_CDR.sflp:33–44`; `size_mul` call in `DMA_SPU.sflp:55`; duplicate `file_adrs` output declarations in `PlayStation_core.sflp:114–116`. Add only `docs/POCKET_SOURCE_DEFECTS.md`. For each item quote the minimum exact source evidence with file and line, classify as confirmed or unresolved, explain what compiler evidence supports that classification, and state any preprocess defines used. Record both default (`DEMO` undefined) and `DEMO`-defined context where applicable; do not silently “correct” likely typos or assert intended hardware behavior. Acceptance is a concise evidence table plus `rg`/compiler commands that another reviewer can reproduce; no source or compiler files change.

### Ready packet Q-L1-05 — diagnostic input preflight

**Copyable assignment:** inventory existing `Pocket/build/apf/` files against `tools/apf/fetch_apf.sh`, the expected Pocket project/constraints and the current local tool availability. Add only `Pocket/diagnostic/inputs.json` and `Pocket/diagnostic/check_inputs.py`. The checker must be read-only, deterministic, and report missing QPF/QSF, Quartus, pixel timing reference, and generated/missing core IP as distinct states. It may hash local cached files; it must not download, fetch, alter APF files, or guess pins/clocks. Acceptance: `python3 Pocket/diagnostic/check_inputs.py` reports each required input and exits nonzero for a deliberately absent required field or hash mismatch. Refer to `docs/POCKET_DIAGNOSTIC_PLAN.md` for the bring-up gates.

### Ready packet Q-L2-02 — diagnostic display/input core

**Copyable assignment:** use [POCKET_DIAGNOSTIC_INPUTS.md](POCKET_DIAGNOSTIC_INPUTS.md), which supplies the pinned primary reference, local cache, exact timing, hashes, pixel-domain interface and acceptance. Own only `Pocket/diagnostic/diagnostic_core.sv` and `Pocket/diagnostic/tb_diagnostic_core.sv`. The source prerequisite is now satisfied; start RTL and Icarus simulation without waiting for Quartus. L3 owns the APF wrapper, reset/CDC review, PLL, constraints and fitting. Report simulation evidence separately from the still-pending hardware gates.

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
