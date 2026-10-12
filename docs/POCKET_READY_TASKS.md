# Work that can continue without the primary agent

Baseline: **77b3f50**, diagnostic RTL/bench and 34-row probe matrix committed.
The three packets below are now complete; their claim records contain results.
Do not duplicate them. Read [rolling checkpoints](POCKET_CHECKPOINTS.md) first. The user authorizes
independent implementation and commits within the packets below. You do not need
the primary agent to wake up, approve a routine choice, or repeat this permission.

Claim one packet by creating `docs/claims/<ID>.md` with provider, UTC time and
starting commit; commit the claim immediately. If that ID is already claimed or
its owned files have someone else's uncommitted changes, choose another packet.
Use an isolated branch/worktree when available. Do not reset/clean the shared tree.
Commit each bounded result, even if it is an explicitly documented failure.
Finish by updating your claim with commands, results, commit, remaining blockers
and whether the packet is done. Own the claim file plus only the listed paths.

## Q-L2-04 — diagnostic regression runner and CI — COMPLETE

**Own:** `tools/pocket/run_diagnostic.py`,
`.github/workflows/pocket-diagnostic.yml`, `docs/claims/Q-L2-04.md`.

Implement a standard-library Python runner that locates the repository from its
own path, creates a temporary build directory, runs Icarus/VVP with timeouts, and
requires the exact diagnostic PASS marker. Propagate compile, simulation,
timeout and missing-tool failures with useful diagnostics. Never rewrite RTL.
Use `Pocket/diagnostic/diagnostic_core.sv` and `tb_diagnostic_core.sv` from 77b3f50.
CI runs the same runner on Linux for changes to those two files, the runner or
its workflow, plus manual dispatch. Do not modify the SFL compiler workflow.

Acceptance: run locally from the repo root and from another directory; both
report `frames=3 checked_pixels=618600`. Verify a deliberate temporary bench
failure returns nonzero without editing the real bench. CI installation needs
Icarus only, not Quartus or proprietary references. If GitHub execution is
unavailable, commit the runner/workflow with Linux result marked pending.

## Q-L2-05 — reproducible pinned diagnostic reference fetch — COMPLETE

**Own:** `tools/apf/fetch_diagnostic_reference.py`,
`docs/claims/Q-L2-05.md`. Cache writes only under gitignored `Pocket/build/reference`.

Read `docs/POCKET_DIAGNOSTIC_INPUTS.md` for the exact source revision, official
archive URL and per-file hashes. Implement a standard-library fetch/verify tool
so a fresh checkout can reproduce the reference cache without the old /tmp file.
Pin revision da3a021b1eaf742604d86d8dc9b33a6666263e6a. Support verifying an existing
cache without network and importing an explicitly supplied local archive. Do not
silently use a newer revision. Extract into a temporary sibling directory,
reject escaping/absolute paths and unsafe links, verify required files against
documented hashes, then publish the cache without overwriting a modified cache.
Keep downloaded/extracted upstream files out of git. Do not modify existing
`fetch_apf.sh`, reference contents, inputs.json or checker owned by another model.

Acceptance: existing-cache verification succeeds; a temporary corrupted copy
fails; local archive `/tmp/psx-apf-template-da3a021.tgz`, if present, imports into
a temporary destination and matches the documented hashes. Missing archive or
network access is a specific pending check, not a reason to leave local verify
mode unimplemented. Report exact outcomes and cache location.

## Q-L1-06 — Pocket diagnostic test card — COMPLETE

**Own:** `docs/POCKET_DIAGNOSTIC_TEST.md`, `docs/claims/Q-L1-06.md`.

Write a short operator test card from `POCKET_DIAGNOSTIC_INPUTS.md` and the
committed RTL. Include fields for bitstream SHA-256, build commit, Quartus version,
fit/timing report and Pocket firmware version. Explain expected eight color bars,
the red/green top-left button patch, frame-held response and reset/reload check.
Provide a results table with not-run/pass/fail and evidence filename fields.
State that a diagnostic pass does not establish PS1 gameplay or FPS.

No bitstream exists yet: leave artifact/build fields explicitly unfilled. Do not
invent a menu path, completed hardware test, timing report or packaging command.
Acceptance: every expected visual follows the pinned contract; all observations
are blank/not-run until a human actually tests. No hardware or Quartus required
to finish and commit this document.

## Already owned or complete — do not duplicate

- Root: Linux full-bench failure reduction, compiler fixes/semantics and future
  APF wrapper/CDC integration. The old p27 native mismatch is a separate issue.
- Q-L1-03: done in 77b3f50; matrix has 34 probes.
- Q-L2-02: done in 77b3f50; diagnostic core passes three-frame simulation and lint.
- Q-L1-04/Q-L1-05: other providers completed local source inventory/preflight.
  Existing owners may commit their own files; do not replace their work.
- `docs/POCKET_BENCHMARKS.md`: another provider's Gunpey addition; preserve it.

If all ready packets are claimed, inspect their claim records for completed
results before starting new work. Do not make speculative edits to shared CPU,
GPU, compiler, timing constraints or memory interfaces to stay busy.
