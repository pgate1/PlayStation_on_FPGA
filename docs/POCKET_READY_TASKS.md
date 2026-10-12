# Work that can continue without the primary agent

Latest received handoff: **2fc51da**, including Claude's three completed packets.
The diagnostic integration checkpoint follows it; use current `pocket-work` HEAD
and record that hash in your claim. Read [rolling checkpoints](POCKET_CHECKPOINTS.md)
first. Completed packets below are retained as history; do not duplicate them.
The user authorizes
independent implementation and commits within the packets below. You do not need
the primary agent to wake up, approve a routine choice, or repeat this permission.

Claim one packet by creating `docs/claims/<ID>.md` with provider, UTC time and
starting commit; commit the claim immediately. If that ID is already claimed or
its owned files have someone else's uncommitted changes, choose another packet.
Use an isolated branch/worktree when available. Do not reset/clean the shared tree.
Commit each bounded result, even if it is an explicitly documented failure.
Finish by updating your claim with commands, results, commit, remaining blockers
and whether the packet is done. Own the claim file plus only the listed paths.
Keep commits local; the latest handoff records the user's no-push constraint.

## READY queue after 2fc51da

| Packet | Suitable work | Independent of |
|---|---|---|
| Q-L2-10 | Reproducible prepared-wrapper structural lint | Quartus, compiler changes |
| Q-L2-11 | Instance-array boundary/rejection tests | APF, native compiler |
| Q-L1-10 | Official Pocket packaging contract | Quartus installation, RTL changes |

### Q-L2-10 — prepared-wrapper lint runner — READY

**Own:** new `tools/pocket/lint_diagnostic_project.py`,
`tools/pocket/tests/diagnostic_vendor_stubs.sv`, `docs/claims/Q-L2-10.md`.

Make root's structural elaboration reproducible. Read `POCKET_DIAGNOSTIC_BUILD.md`
and `prepare_diagnostic.py`; take a prepared-project directory and first reuse
the read-only auditor. Invoke Verilator on `core_top`, its actual bridge/common
sources and both diagnostic modules with interface-only `mf_pllbase` and
`mf_datatable` stubs derived from the pinned declarations. Keep stubs outside
the prepared Quartus project, label them simulation-only, and do not insert them
into QSF. Do not alter vendor sources, overlay, RTL, SDC or existing runner.

Use bounded subprocess timeouts and report tool version, full command, output
and exit code. Preserve warnings; existing vendor warnings may be nonfatal but
must not be reported as clean lint. Missing tools, corrupt project inputs or
unresolved modules must fail. Acceptance: local prepared project structurally
elaborates; a temporary copy with a missing module is rejected (update only that
copy's manifest when deliberately testing elaboration after a valid audit).
State explicitly that PLL/bridge behavior, synthesis and timing remain untested.

### Q-L2-11 — instance-array boundary tests — READY

**Own:** new `tools/sflc/tests/test_instance_array_boundaries.py`,
`docs/claims/Q-L2-11.md`. Do not edit `sflc.py` or the shared test runner.

Use standard-library unittest and temporary tiny SFL+ inputs through the public
compiler entrypoint. Cover missing element, negative index, mixed suffix widths,
nonconstant index, ordinary indexed memory and valid uppercase hex/padded names.
Check whether a similarly named scalar signal can be mistaken for an instance;
record observed behavior rather than silently changing compiler semantics.
Also cover `ch[i].method(args).output` inside a generator and report the precise
currently unsupported boundary. Do not blank blocks in real sources or claim
native equivalence. Include a documented standalone command and mutation check
showing at least one routing/bounds expectation detects a deliberate wrong map.
If a case reveals a compiler defect, commit the reproduction and failure evidence
without making the default suite falsely green or expanding ownership.

### Q-L1-10 — diagnostic packaging contract — READY

**Own:** new `docs/POCKET_DIAGNOSTIC_PACKAGING.md`, `docs/claims/Q-L1-10.md`.

Read the pinned template metadata and official Analogue/openFPGA documentation.
Determine the exact transformation from a newly generated RBF to `.rbf_r`,
required core/platform JSON fields and SD directory layout, citing source URLs
and the pinned template revision. Distinguish byte/bit transformation from a
filename change; do not guess commands or copy the reference bitstream as ours.
Record which assets are present and which are missing. Produce a short operator
checklist whose artifact fields remain blank until Quartus supplies a new build.
No downloads of binaries, hardware writes, release uploads or unrelated license
decisions are needed. If official evidence is inaccessible, commit exact gaps
and accessible evidence; do not call the packet a verified packaging procedure.

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

## Q-L2-09 — prepared-project input auditor — COMPLETE (ff0decc)

**Own:** `tools/pocket/check_diagnostic_project.py`, `docs/claims/Q-L2-09.md`.
Starting baseline: the commit adding `tools/pocket/prepare_diagnostic.py`; find it
with `git log -1 --oneline -- tools/pocket/prepare_diagnostic.py`.

Read [diagnostic build contract](POCKET_DIAGNOSTIC_BUILD.md). Implement a read-only,
standard-library CLI taking a prepared project directory. Validate schema-1
`diagnostic_build.json`, the pinned reference revision/device/project, and all
recorded project file hashes. Reject missing files, malformed/traversing manifest
paths and hash drift; never execute QSF/Tcl or change the build/cache. Check that
QSF includes both diagnostic SV inputs, top apf_top and device 5CEBA4F23C8. Report
stored not-run/pending qualification separately: input verification is not a
Quartus or timing pass. Do not reject legitimate later Quartus output files merely
because they are not input entries, and never certify a bitstream from existence.

Acceptance: prepared project validates; a temporary copy with a changed diagnostic
SV file fails; a temporary manifest naming a missing or escaping input fails;
files remain unchanged. No Quartus or root approval is needed to complete this
packet. Do not modify the preparer, overlay, RTL, runner or existing claims.

## Q-L1-07 — remaining generator/source inventory — COMPLETE (bf4b1a2)

**Own:** `docs/POCKET_GENERATOR_INVENTORY.md`, `docs/claims/Q-L1-07.md`.
Inventory par/any/alt/join generator sites in the original SFL+ sources (exclude
test fixtures and build caches). Record file/line, literal/constant bounds,
iteration count where unambiguous, and body categories (registers, memory writes,
instances, selectors). Separate implemented par/any/alt from unsupported join and
instance-array constructs; cite current compiler limitations. Include the newly
exposed R3000A cache_hit_reg reference and any actual declaration found, without
inventing a fix or signal width. Preserve CRLF/non-UTF-8 bytes: read only, use
`rg -an` or decode bytes explicitly. This supplies bounded evidence for the next
strong compiler owner. No source edits, native tool or synthesis needed.

## Q-L1-08 — Quartus build-host research — COMPLETE

`task_packets` produced `docs/POCKET_QUARTUS_BUILD.md` and its claim record;
root reviewed them for the diagnostic integration checkpoint. No installation
or Quartus build performed.

## Already owned or complete — do not duplicate

- Root: APF project preparation/overlay and compiler semantic decisions. Linux
  scoreboard portability is fixed; the p27 native mismatch remains separate.
- Q-L2-07: reset synchronizer and two-bench runner are complete in the diagnostic
  integration checkpoint; local simulation/lint pass, extended Linux CI pending.
- Q-L1-09: constant-indexed instances complete in `4bfb2f8`; local 16-group suite
  passes. Native equivalence and nested invocation targets remain unresolved.
- Q-L1-03: done in 77b3f50; matrix has 34 probes.
- Q-L2-02: done in 77b3f50; diagnostic core passes three-frame simulation and lint.
- Q-L1-04/Q-L1-05: other providers completed local source inventory/preflight.
  Existing owners may commit their own files; do not replace their work.
- `docs/POCKET_BENCHMARKS.md`: another provider's Gunpey addition; preserve it.

If all ready packets are claimed, inspect their claim records for completed
results before starting new work. Do not make speculative edits to shared CPU,
GPU, compiler, timing constraints or memory interfaces to stay busy.
