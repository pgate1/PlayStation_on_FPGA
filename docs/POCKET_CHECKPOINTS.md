# Rolling checkpoints

Read this file before claiming work. The dated handoff remains historical evidence;
new entries here record current ownership, discoveries and commits. Update after
each bounded change or significant finding, and at least every 15 minutes during
longer work. A checkpoint may explicitly report incomplete work or failing tests.

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
