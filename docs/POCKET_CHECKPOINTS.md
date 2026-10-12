# Rolling checkpoints

Read this file before claiming work. The dated handoff remains historical evidence;
new entries here record current ownership, discoveries and commits. Update after
each bounded change or significant finding, and at least every 15 minutes during
longer work. A checkpoint may explicitly report incomplete work or failing tests.

## 2026-10-12 19:22 UTC — Linux regression fixed; three independent packets active

- **Linux PASS:** all 15 compiler groups and the diagnostic's 3-frame/618600-pixel
  scoreboard pass run [38296978627](https://github.com/ollisulopuisto/PlayStation_on_FPGA/actions/runs/38296978627),
  isolated snapshot `9ccdab6`. Root also reran all 15 groups locally successfully.
- **Fix:** only generator scoreboard tasks changed from automatic to static.
  Calls are sequential/nonrecursive. On Icarus 11 the old full bench read X on
  output wires even though internal cells held zero; static tasks passed all
  unchanged checks. Compiler/emitted memory logic did not change. Reduction and
  reproduction are documented in `POCKET_BANK_INIT_REPRO.md`. Native p27 mismatch
  and wide reg_ws compatibility remain unresolved; do not conflate these issues.
- **Completed commits:** `cd7ed19` initial claim checkpoint; `77b3f50` reviewed
  diagnostic RTL/bench and probe matrix; `c0f86ea` autonomous provider packets.
- **Active smaller-model claims:** diagnostic_core -> Q-L2-04 (runner/workflow);
  task_packets -> Q-L2-05 (reference-cache fetch/verify); cache_boundaries ->
  Q-L1-06 (operator test card). Each has a separate `docs/claims/` record and owns
  disjoint paths. Root reviews/stages results promptly; no duplicate assignments.
- **Other provider report:** user relayed that all five Pocket HDL benches pass
  and results were written to `scratchpad/progress.md`. That path is absent in
  this checkout at review time; result is recorded as reported, not independently
  inspected. Do not rerun those benches solely to duplicate that work.
- **Next root task:** review the three packets and advance the independent APF
  diagnostic integration path; compiler semantic qualification remains open.

## 2026-10-12 17:50 UTC — diagnostic simulation and matrix complete

- Diagnostic RTL and bench have been reviewed, including removal of the RTL
  divider, an independent arithmetic color scoreboard, actual-output frame totals
  and a watchdog. Root reran Icarus: **PASS**, 3 frames / 618600 checked pixels.
  Verilator lint passed without warnings. This is a pixel-domain simulation;
  APF wrapper, Quartus fit and physical Pocket test remain open.
- Q-L1-03 matrix refresh completed against f983b03: **34 probes**; p21 status
  corrected; p27 mismatch kept distinct from conversion success; p28 comparison
  recorded. Agent reran 15 local groups, 15 combinational reference cases and
  six sequential cases successfully. p27 still fails at the known cycle 4.
- Other provider Q-L1-05 now records project/timing inputs correctly. Read-only
  checker reports all 13 APF hashes and reference files present; only quartus_sh
  blocks this preflight. Its two uncommitted files remain with their owner.
- Linux diagnosis is running on isolated branch snapshot eea8b1f, run 38286792631.
  The full bench fails, but a reduced bench reads initialized cells correctly.
  Do not label this a memory-initialization compiler bug yet; root continues
  reducing the full-bench interaction. Compiler semantics have not changed.
- Next independent work: diagnostic simulation CI/runner, reference-cache fetch
  automation and artifact manifest checks can proceed without root. Exact packets
  will be placed in the model queue; no Quartus prerequisite for simulation CI.

## 2026-10-12 17:20 UTC — resumed from 42020ac

- **Observed state:** local branch still ends at documentation commit `42020ac`,
  compiler checkpoint `f983b03`. Other providers' uncommitted diagnostic manifest
  now records the pinned project and timing inputs. `POCKET_BENCHMARKS.md` adds
  Gunpey with user-backup hashes. Preserve these edits and their ownership.
- **Root claim:** investigate the reproducible Linux bank initialization failure.
  Compiler files and isolated CI validation are owned by root for this packet.
  No semantic change is justified yet; native p27 mismatch and wide reg_ws
  compatibility remain separate unresolved problems.
- **Delegated claim:** internal smaller-model agent `diagnostic_core` owns only
  `Pocket/diagnostic/diagnostic_core.sv` and `tb_diagnostic_core.sv` (Q-L2-02).
  It will implement and simulate the already pinned contract. Other providers
  should not create competing versions. Root will review before committing.
- **Read-only review:** `task_packets` checks other providers' completion state;
  it owns no edits. Existing manifest/checker/source-inventory files stay with
  their providers. Do not restage or overwrite them.
- **Still available:** Q-L1-03 result-matrix reconciliation against f983b03 is
  independent; record its snapshot explicitly because compiler work has resumed.
  Quartus installation/build provisioning is also unclaimed; do not report a
  fitted diagnostic or PS1 project from reference-project availability alone.
- **Evidence:** git status/log and current diagnostic manifest inspected. No new
  test/build result yet. Next checkpoint: Linux failure reduction and/or reviewed
  diagnostic simulation, whichever completes first.

Hardware state remains unchanged: no new Pocket bitstream or gameplay result.
