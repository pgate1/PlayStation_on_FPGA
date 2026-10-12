# P00 build recovery — dependency status and plan

**Current update (2026-10-12):** compiler checkpoint f983b03 adds bounded generators.
Fifteen groups pass locally and on Linux after a static-task bench fix (38296978627).
Six sequential reference cases pass; parallel-memory p27 is a known mismatch.
Wide reg_ws also has an unresolved SFL+ versus archived-native semantic gap.
Full-core compilation and a Pocket build remain open. Start with the exact
[handoff](POCKET_HANDOFF_2026-10-12.md), then [compiler limits](POCKET_SFLC.md).
The dated sections below are recovery history, not the current capability list.


Checked 2026-10-11. Evidence is from GitHub API queries and web search; pgate1.at-ninja.jp could not be fetched from this session.

## Snapshot identity

This folder equals upstream `github.com/pgate1/PlayStation_on_FPGA` HEAD **`e87165c42e`** (2026-10-06, "run parallel even during GTE/MUL/DIV processing"), compared by git blob hash after CRLF→LF normalization. The only differences are local edits:

- `Cache_IR.sflp:103`, `Cache_Texture.sflp:153` — the P02 `offset==0` → `offset==1` fix (upstream still has the bug).
- Upstream line 58/82 comments in those two files are double-encoded mojibake; the local copy has the original Shift-JIS bytes. Local is the better copy.

Upstream is active (4 commits on 2026-10-06). Rebase our work on upstream before integration; do not assume this snapshot stays current.

## Toolchain

| Tool | Status | Source |
|---|---|---|
| `sflp` (SFL+ → SFL + `.h` preprocessor) | **Not public.** pgate1 states it was never released | pgate1 NES_on_FPGA event page, "はじめてのSFL+" memo |
| `sfl2vl -O2` (SFL → Verilog) | **Not freely downloadable.** Bundled with Overtone's NSL Core; obtained by request. Evaluation build reportedly capped at 2,000 lines | pgate1 SNES page; pgate1 "論理回路考古学のススメ" PDF; ip-arch.jp has no download |
| Verilator | Used only for lint (`--lint-only PlayStation_core.v -y demo`) | Makefile |
| Quartus | Device 5CEBA4F23C8. Installer + Cyclone V package exist in MIRLO64 tree (Linux), not installed | — |

Largest single source: `GeometryTransformationEngine.sflp` 1,902 lines; total 13,671 lines across all `.sflp`. A 2,000-line per-file cap might fit pre-expansion, but this is unverified (cap semantics and post-`sflp` sizes unknown).

SFL+ features visible in sources (for scoping a replacement): `%i "x.h"` includes of generated interface headers, C-style `#ifdef/#define`, `circuit`, `sel`, `instrin name(args)` combined argument syntax, `instrout`, `instrself`, `reg_wr/reg_ws`, `mem`, `stage/stage_name/state/first_state/goto/generate/finish`, `par/any/alt/if/else`, `switch/case` (MDEC), `declare ... interface` for Verilog leaf modules.

## Missing build inputs

| Item | Used by | Status | Recovery |
|---|---|---|---|
| `apf_top`, `core_bridge_cmd`, `synch_3` (`common.v`), `io_*`, `mf_datatable`, `mf_ddio_bidir_12`, `pin_ddio_clk`, `apf_constraints.sdc`, `ap_core.qpf/.qsf` | `Pocket/core_top.v` | **Recoverable** | `github.com/open-fpga/core-template` `src/fpga/apf/*`, `src/fpga/core/*`. Pin revision; check Analogue license terms |
| `main_pll_0002` | `core_top.v:775` (74.25 MHz in → clk_50, dram_ctrl_clk, dram_clk, clk_25, clk_25_90deg) | Regenerable | Quartus PLL IP; exact frequencies/phases are not in the source except names. `dram_clk` is also tied `'h0` at line 292 (driven twice — check) |
| `vjtag_uart.h` + `.v` | `Pocket/core.sflp` (`../../../hdl/USB-JTAG/DE0-CV/`) | **Recoverable** | `github.com/pgate1/USB-Blaster_UART` `DE0-CV/vjtag_uart.{h,v}`. Debug only; can likely be removed for Pocket |
| `sram_ctrl.h` + impl | `Pocket/core.sflp` (`../../../Pocket/`) | Missing, pgate1 private | Write a small async-SRAM controller (Pocket 256 KiB) to the interface implied by `core.sflp` |
| `sdram128_burstn_ctrl_100` | `core_top.v:680` | Missing, pgate1 private | Planned replacement anyway: MIRLO64 `sdr_ctrl/sdr_phy` behind `Pocket/rtl/psx_mem_frontend.sv` (P04) |
| `ram_320x240x15_dp.sflp/.h` | `view_ram_ctrl.sflp:4` | Missing, pgate1 private | Dual-port BRAM; easy to write in Verilog, but P06 plans to remove these buffers |
| `view_ram_ctrl_one.sflp`, `pseudo_cdrom_data.sflp` | Root Makefile only | Missing; no `.sflp` references them | Probably not needed for Pocket; drop from manifest |

Directory layout implied by include paths: `<root>/hdl/USB-JTAG/DE0-CV/`, `<root>/Pocket/sram_ctrl.h`, project at `<root>/<a>/<b>/Pocket/core.sflp`.

## Routes to a working build

1. **Ask pgate1** (best payoff, needs the user): request `sflp` or, failing that, the generated `.v` for the current HEAD plus `sram_ctrl`, `sdram128_burstn_ctrl_100`, `ram_320x240x15_dp`. Offer the P02 cache fix in return. The author is active.
2. **Request NSL Core/sfl2vl from Overtone** (non-profit license). Solves only the second stage; `sflp` still missing.
3. **Write our own SFL+ → Verilog compiler.** No third-party dependency, but large (a full SFL semantics implementation: stages/tasks, control-terminal activation, `any/alt` priority, `mem` inference) and impossible to validate against a reference compiler without route 1 or 2. Validate against the DE2-115 `.sof`/Pocket bitstream behavior only indirectly.
4. **Abandon SFL for new work:** keep SFL modules frozen as generated Verilog (needs 1 or 2 once) and write all new blocks in SystemVerilog. Already the roadmap's direction.

Recommendation: route 1 now; start route 3 only as a parser feasibility spike (parse all 13.7k lines, enumerate constructs) if route 1 gets no answer.

## Update 2026-10-11 (later): sfl2vl recovered, evaluation-limited

- **Binary:** `sfl2vlbin-i386-linux-20100412.tar.gz` (SHA-256 `b67fd7216f5f5ca4222ef77a7d68c1c1e19dd45ebf6f5ad5e0522668f57724c1`), archived by the Wayback Machine from `overtone.co.jp/binaries/`. Contains `sfl2vlbin.exe` (i386 ELF, needs only libc), `sflpp.exe` (handles `%i`, `%d`, `#ifdef`), and the `sfl2vl`/`sfl2declare` wrapper scripts. `sfl2declare` = `sfl2vlbin.exe -declare`, which generates the `.h` interface files.
- **Where it runs:** GitHub Actions `ubuntu-22.04` with `libc6:i386`. Workflow `.github/workflows/sfl2vl.yml` on the public fork `ollisulopuisto/PlayStation_on_FPGA` (branch `pocket-work`). It downloads the binary at run time and checks its hash; the binary is not committed or uploaded.
- **License:** no license file, so evaluation mode. **Hard limit: 500 input lines** ("Number of lines is over!" at line 499). Do not try to work around it. Generated files say they may be used for educational/personal projects. A non-profit license (reportedly 2,000 lines) or a paid license would have to come from Overtone/IP ARCH.
- Also archived: `ip-arch.jp/binaries/sfl2vlwin.zip` (Windows MSI, 2004), not tested.

### Probe results (`tools/sflc/probe`, run 38168699381)

Accepted natively by sfl2vl 20100412: `if/else`, `sel`, binary `-`, `!=`, `++`/`--`, `reg x<n> = v`, `mem ... = {0}`, `%d`, `#ifdef`, `N#`, `/|`, `@`, `any/alt ... else`, `declare ... interface`, `circuit`/`module`.

**Operator semantics:** strictly left to right, no precedence: `a || b + c` becomes `({a,b})+c`, `c==d & e<0>` becomes `((c)==(d))&(e[0])`. This matches pgate1's code (e.g. `CDROM_controller.sflp:408` min*60+sec, GTE `(MAC1||0x000)+x`). Only 14 unparenthesized mixed-operator chains exist in the sources.

Not accepted, so these must be what `sflp` rewrites:
- declarations after use (sfl2vl is single-pass: `instr_arg` must follow all declarations; task arguments must be declared before `stage_name`)
- `instrin/instrout/instrself name(args)`, which becomes a declaration plus `instr_arg`
- `switch/case/default`
- `+=`, `-=`, `&=`, `|=`
- `par/alt/any/join(i=0;i<N;i++)` generators (index `i` acts as a constant of width ceil(log2 N); `ch[i]` becomes `ch_00`..)
- states used without `state_name`
- declarations, submodule instances and `instruct` nested inside blocks/stages/`if`
- string constants (`"FPGA"`)

### Consequence

The archived sfl2vl cannot build the large modules (R3000A, GTE, GPU, CDROM, core) under the 500-line limit. It is still valuable as a **reference oracle**: any self-written SFL+ to Verilog compiler can be checked against it on small probes and on the real modules that stay under 500 lines.

Parser spike: `tools/sflc/sflp_parse.py` parses all 44 `.sflp` files (16,152 lines). Construct counts: 108 stages, 306 states, 359 `instruct`, 189 `generate`, 382 `goto`, 30 `switch`, 36 generators.

## Milestone 1: own SFL+ combinational subset (2026-10-11)

`tools/sflc/sflc.py` (uses `sflp_parse.py`) translates combinational SFL+ circuits to Verilog. Verified against sfl2vl 20100412 output by random co-simulation in Icarus (4000 vectors each, `$S/cosim/cosim.py`):

- PASS: p01_ifelse, p03_sel, p04_ops, p09_prec, p11_pp, p12_unops, p14_any_alt, p16_circuit_kw, real bsr_s16 (`bsr_s16.sflp`, 4000 vectors each)
- Skipped (sequential reference, not compared): p07_init, q_lines00400

Operator rules confirmed from the reference: `@` is binary XOR; unary `^` is bitwise NOT; `N#x` sign-extends `x` to N bits, where `x` is a name or a constant slice of a name.

`any`/`alt` semantics (from p14 reference): `any` arms are independent (each guard ORed in; `else` = no arm matched). `alt` is first-match priority. `alt` without `else` is rejected as unverified.

`instrin name(args)`: the reference (bsr_s16) turns it into a 1-bit input port `name`; the args stay the circuit's own ports and add no logic.

Not supported (fails loudly with NotImplementedError): `instrout/instrself` (no reference output yet), `switch`, `inst` submodules, `mem`, stages/states, indexed assignment targets, generators, `alt` without `else`. p15 is out of scope.

Limits: the generator is not a replacement for sfl2vl's output format; only functional equivalence on the probes is checked.

## Milestone 2: sequential blocks and cache validation (2026-10-12)

`tools/sflc/sflc.py` now lowers reset variants, register/memory updates, local
control calls and arguments, lexical locals, switch and one-task stages. It
emits SystemVerilog and optional conflict/regeneration assertions. The actual
cache sources pass suffix-fill, alignment, replacement and reset fixtures;
reverting either original offset fix is detected. The previous nine
combinational reference comparisons still pass. No sequential equivalence or
complete Pocket build is claimed.

Run `python3 tools/sflc/tests/run_tests.py`; detailed results, semantic limits,
and the next L3 work sequence are in [POCKET_SFLC.md](POCKET_SFLC.md).
The rejected native `p13_stage` was never a stage oracle. New p17–p19 probes
remove its invalid input-terminal `instr_arg` declaration; independent archived
compiler runs remain pending.
