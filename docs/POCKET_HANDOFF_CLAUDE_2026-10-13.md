# Handoff: what the Claude session did while the root (Codex) agent was out

Written 2026-10-13 ~00:55 local for the Codex agent returning after its usage
limit reset (01:10). Read this, then `POCKET_CHECKPOINTS.md` and
`POCKET_READY_TASKS.md`. Branch `pocket-work`; nothing has been pushed.

## Commits since your last (`5c179b7`), all unpushed

| Commit | What |
|---|---|
| `86aa4b7`, `ff0decc` | Q-L2-09: read-only prepared-project auditor `tools/pocket/check_diagnostic_project.py`. Real `Pocket/build/diagnostic-reviewed` → exit 0 "INPUTS VERIFIED"; 11/11 negative/tolerance cases on temp copies. Not a Quartus pass. |
| `dbf678a`, `bf4b1a2` | Q-L1-07: `docs/POCKET_GENERATOR_INVENTORY.md`. 36 generator sites in 44 sources (par 23, any 5, alt 2, join 6). 30 par/any/alt are implemented-type; 17 of them index an instance array (14 DSP `ch[i]`, 3 PlayStation_core `timer[i]`); 6 `join` unsupported (5 DSP, 1 PAD_controller:298). `cache_hit_reg` is used only at `R3000A.sflp:195` and is declared nowhere; width not inferred. |
| `c1e7ab9`, `4bfb2f8` | Q-L1-09: `sflc.py` now resolves `name[<constant>]` to a declared instance `name_XX`. Fixture `tests/instance_arrays.sflp` + `tb_instance_arrays.sv`: `PASS instance_arrays checks=4032`; mutant caught; `run_tests.py` has `test_16`. `python3 -I tools/sflc/tests/run_tests.py` → 16 tests OK. |

Compiler change is small (`Scope.instance_element`, ~19 lines): digit count is
taken from the declared `name_<UPPERCASE HEX>` names, the element must be
declared, mixed digit counts error, runtime index stays `NotImplementedError`.
This is **inferred** from `ch_00..ch_17` and `timer_0..timer_3`; no native
oracle exists (archived sfl2vl rejects generators, p08 log says syntax error,
and `sflp` is missing).

## Current compiler frontier on real sources

- `DigitalSignalProcessor.sflp`: first error `join generator`. With the join
  blocks blanked in a scratch copy it passes `ch[i]` and stops at `nested
  invocation target` (`ch[i].io_get(io_A<3:0>).io_Dout`).
- `PlayStation_core.sflp`: `duplicate interface port file_adrs` (source defect,
  see `POCKET_SOURCE_DEFECTS.md`; four more defects listed there).
- `R3000A.sflp`: undeclared `cache_hit_reg`.
- **`join` is the main open semantic decision.** Self-referencing uses:
  `acc := acc + x_i` (DSP 111–128), `disp_env = (ch[i].disp_env) || disp_env`
  (DSP 154), `checksum = data_buf[i] @ checksum` (PAD_controller 298). The base
  value in iteration 0 and the ordering are unspecified locally. I did not guess.
  The author's notes (`pgate1.at-ninja.jp/memo/SFLP/`) were unreachable from the
  Claude sandbox (connect failed); you may be able to read them.

## State of the tree (do not assume it is clean)

Uncommitted, **not mine**: `.github/workflows/pocket-diagnostic.yml`,
`Pocket/core.sflp`, `docs/POCKET_CHECKPOINTS.md`, `docs/POCKET_READY_TASKS.md`,
`tools/pocket/run_diagnostic.py`, and the untracked `Pocket/diagnostic/*`,
`Pocket/rtl/{ram_320x240x15_dp,sram_ctrl}.sv`, `Pocket/tb/*`, `hdl/`,
`docs/POCKET_{DIAGNOSTIC_BUILD,QUARTUS_BUILD,SOURCE_DEFECTS}.md`,
`docs/claims/Q-L1-08.md`, `Q-L2-07.md`, `tools/apf/fetch_apf.sh`,
`tools/pocket/{build_inputs.json,check_build_inputs.py,check_p00_probes.py,prepare_diagnostic.py}`.
Also modified: tracked `tools/sflc/__pycache__/sflp_parse.cpython-312.pyc`
(should not be tracked; needs a `.gitignore`/`git rm --cached` decision).

Mine but uncommitted:
- `docs/POCKET_READY_TASKS.md`: two heading edits inside your uncommitted text
  (Q-L2-09 and Q-L1-07 → `COMPLETE (ff0decc)` / `COMPLETE (bf4b1a2)`). I did not
  commit it because the file's whole Q-L2-09/Q-L1-07/Q-L1-08 sections are your
  uncommitted text. Q-L1-09 is not listed there yet.
- `docs/POCKET_BENCHMARKS.md` row B6: GUNPEY hash edit (another provider's Gunpey
  line must be kept). Hashes: `.bin` `c04448b3…16f5`, `.cue` `52126e75…8fe3`, zip
  `51a6d3b7…7208`; backup at `/Volumes/backup/games/roms/sony/psx/Gunpey (Japan).zip`.

## Verified this session (all local, exit 0)

- `tools/sflc/tests/run_tests.py`: 16 tests OK.
- diagnostic_core Icarus: PASS, frames=3 checked_pixels=618600.
- Pocket HDL benches: psx_mem (default/min/wide), ram_320x240x15_dp (200000 ops),
  sram_ctrl (4002 cmds) PASS.
- `check_p00_probes.py` OK (28-row matrix in `tools/pocket/p00_probe_matrix.json`).
- `Pocket/diagnostic/check_inputs.py` exits 2: `quartus_sh` missing and PS1-only
  IP missing. Quartus is not on PATH.

## Still blocked or open

- Step one (video) needs Quartus and a bitstream; none exists. Step two (audio)
  not started. Nothing has run on hardware.
- Open decisions for the user: `check_build_inputs.py` version; committing your
  compiler/test changes; `.gitignore`/`__pycache__`; Overtone/NSL licence; APF
  distribution licence; `sram_ctrl.h` include; remaining `Pocket/core.sflp`
  parts (Claude was told not to touch them).
- Q-L1-08 (Quartus host research) and Q-L2-07 (reset synchronizer) are claimed by
  other providers.

## Constraints the user set (keep them)

Stay on `pocket-work`, never push, stage exact paths only, preserve others'
uncommitted work, do not reset/clean the shared tree. No 500-line-limit
work-arounds (never compact or split real sources; use tiny probes). No pirated
tools or licences, no torrents, no downloads from unknown sources, no licence
requests or maintainer contact. Do not commit the sfl2vl binary. Do not send the
user's e-mail address to unrelated services. Commit trailers for Claude commits:
`Co-Authored-By: Claude …` and `Claude-Session: …`; commits are authored as
Olli Sulopuisto.

## Tooling notes

Shell is zsh: no `xargs -a`; unmatched globs abort; use `rg -an` (the `grep`
function misbehaves) and `LC_ALL=C` on CRLF/latin-1 sources. `rm -rf` is aliased
to `trash` here. `cell` is a SystemVerilog keyword and breaks downstream
elaboration of an instance with that name. The Claude sandbox blocked scheduling
an unattended `codex exec`; this file exists because that restart is manual.
