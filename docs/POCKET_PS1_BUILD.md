# Pocket PS1 project, milestone 1 (Q-L1-14)

Status (2026-10-13): a complete Pocket PS1 Quartus project (APF template, the
author's Pocket top, the PS1 core with the time-shared SPU and sound enabled)
is prepared reproducibly and runs through Quartus 25.1 synthesis and fit on
ristisana. **It does not fit the Pocket's 5CEBA4F23C8.** Nothing here has
booted, been checked against real memory, or been timing-reviewed.

```sh
# real Pocket build (template QSF, real APF pins), two reverb variants
PYTHONDONTWRITEBYTECODE=1 python3 -I tools/pocket/prepare_ps1_project.py \
    --output Pocket/build/ps1-a4-buf --check
PYTHONDONTWRITEBYTECODE=1 python3 -I tools/pocket/prepare_ps1_project.py \
    --output Pocket/build/ps1-a4-spuram --reverb-in-spu-ram --check
# information only: same F23 package and pins on the larger 5CEBA9
... --output Pocket/build/ps1-a9-buf --device 5CEBA9F23C8
# then, in a copy of the directory: quartus_sh --flow compile ap_core
```

`--check` elaborates the translated `core` hierarchy in Icarus (structural only).
Other information-only switches: `--qsf-profile neutral` (Quartus default
synthesis settings), `--option reverb-off` (keeps the upstream reverb tie).

## What the preparer assembles

| Part | Source | Treatment |
|---|---|---|
| APF project, pins, bridge, SDC base | pinned template `core-template-da3a021…` (cache under `Pocket/build/reference/`) | copied; `output_files`/`db` excluded; SignalTap assignments removed and `ENABLE_SIGNALTAP OFF` |
| `core/core_top.v` | `git show HEAD:Pocket/core_top.v` | patched copy (fixes C1–C8) |
| `ps1/sfl/` | `prepare_core_sources.py --shared-spu [--reverb-in-spu-ram]` | lead's tool, unchanged |
| `ps1/sfl/Pocket/core.sflp` | `git show HEAD:Pocket/core.sflp` | patched copy (T1–T9); the working-tree copy is never read |
| `ps1/sfl/view_ram_ctrl.sflp` | prepared copy | patched copy (V1, V2) |
| `ps1/rtl/core.sv` | `sflc.py --hierarchy --register-banks core.sflp` | generated |
| `ps1/rtl/reverb.sv` | `sflc.py --hierarchy reverb.sflp` | generated (the shared DSP instantiates it) |
| `core/main_pll_0002.v` | template `mf_pllbase_0002.v` | module renamed, five outputs re-specified |
| `core/core_constraints.sdc` | new | PLL outputs one group, APF clocks asynchronous |
| replacements | see "Uncommitted inputs" | copied after SHA-256 check |
| `ps1_build.json` | — | hashes of every input, tool and prepared file; variant; validation state |

All edits are in `Pocket/source_fixes/pocket_top_fixes.json`: each fix is pinned
to the SHA-256 of its source and must match exactly once (CRLF/latin-1 kept).

### Fix ledger

Class A = mechanical (paths, names, dead ports). Class B = a design decision.

| ID | File | Class | Change |
|---|---|---|---|
| T1, T2 | core.sflp | A | include paths: `sram_ctrl_sfl.h`, `vjtag_uart.h` next to the sources |
| T3 | core.sflp | A | `sram_ctrl` instance becomes the shim type `sram_ctrl_sfl` |
| T4 | core.sflp | B | remove the ties `sw_reverb_off`, `sw_spu_off`, `sw_spuenv_off` (sound on) |
| T5, T7 | core.sflp | B | export `sound_L/R<21>` = `psx.voice_L/R` |
| T6 | core.sflp | B | export `run33_o` in the same branch as `psx.run33()` |
| T8, T9 | core.sflp | B | restore the commented SPU RAM requests/acks on `sdram_read/sdram_write`, 1 halfword; base halfword `0x180000` (byte `0x300000`). The old base `0b000100` overlaps VRAM in the 25-bit map |
| V1, V2 | view_ram_ctrl.sflp | A | private RAM header replaced by the `ram_320x240x15_dp_sfl` shim |
| C1 | core_top.v | B | loader strobe synchronized into `clk_50` (the adapter's command clock) |
| C2–C4 | core_top.v | A | drop the `set_bram`/`bram_*` ports (commented out in core.sflp), tie `set_bram`, connect audio, declare new nets |
| C5–C7 | core_top.v | B | the private `sdram128_burstn_ctrl_100` becomes `sdram128_burstn_adapter`; `sdr_phy` drives `dram_dq`, `dram_cke` and `dram_clk` (DDIO); PLL output 2 feeds the PHY |
| C8 | core_top.v | B | silence generator replaced by `pocket_audio_out #(.SAMPLE_SRC(1))` (docs/POCKET_AUDIO_OUT.md integration notes) |
| O-RVB | core.sflp | info | option `reverb-off`: keep `psx.sw_reverb_off()` |

Generated files (inline in the JSON): `sram_ctrl_sfl.h`, `ram_320x240x15_dp_sfl.h`
and `pocket_top_shims.v`. The SRAM shim reports `ack = ~busy` because core.sflp
uses `sram.ack` as "idle", while `Pocket/rtl/sram_ctrl.sv` exposes a pulse.

## SDRAM adapter (`Pocket/rtl/sdram128_burstn_adapter.sv`)

Stands in for the author's private `sdram128_burstn_ctrl_100` with MIRLO64's
`sdr_ctrl` (in-order 32-bit word requests, open-page, refresh) and `sdr_phy`
(half rate, BL2, CL3). `sdram128_burstn_wordside` turns one halfword burst
(1–8 halfwords, 128-bit data, 16 byte enables, odd starts touching up to five
words) into word requests and gathers read words by tag.

Assumptions (the original controller is not available):

- **ack** is a level "idle/done": `ack = ready & idle & ~(read|write)`. core.sflp
  registers it once and issues only while that copy is 1, and treats 1 as the
  completion of the previous command. The registered copy is 0 in the cycle
  after every strobe; it rises after read data is in `dout` or the last write
  word is accepted (sdr_ctrl is in order, so later reads observe the write).
- `burst` 0 or >8 is treated as 8; bytes beyond `2*burst` are masked on
  writes; `dout` bytes beyond the burst are not cleared; write wins if both
  strobes are high; strobes while busy are dropped and counted (`dropped`).
- Clocks: commands and `sdr_ctrl` on `clk_50`; `sdr_phy` on `dram_ctrl_clk`
  (100 MHz, aligned) and PLL output 2 (100 MHz, +90°) for the SDRAM clock.
  `T_REFI` rescaled to 380 cycles at 50 MHz; other counts are conservative.
- `la_valid` (row look-ahead) is unused.

Evidence (Icarus 13, local):

- `Pocket/tb/tb_sdram128_burstn_adapter.sv` (wordside vs behavioural word
  controller, random backpressure/latency, core-like driver):
  `PASS ... 9980 reads, 10020 writes ... seed 1`, likewise seeds 7 and 42
  (20,000 ops each). Mutations caught: odd-start shift, ack convention, length mask.
- `Pocket/tb/tb_sdram128_burstn_pins.sv` (adapter + sdr_ctrl + sdr_phy vs a
  CL3/BL2 SDRAM model with command legality checks): `PASS ... 1951 reads,
  2049 writes, 1898 ACT, 108 REF, tout 12000 ps, seed 1`, seeds 2 and 3 pass.
  **Hardware item:** with the PHY's fixed read latency, data is captured
  correctly only if it appears 10–14 ns after the SDRAM clock edge (5–9 ns
  fail, one beat early or missed). Real tAC is about 5.4 ns, so the SDRAM clock
  phase / IO delay at 100 MHz must be chosen on the board (MIRLO tuned it at
  125.664 MHz).

## Results

All runs: ristisana, Quartus Prime Lite 25.1std.0 Build 1129, template QSF
settings, the template's real pin assignments, sources re-prepared after
source fix F8 and sflc `dca809a` (manifest `core_sources_applied`:
F3 F6 F6b F5 F8 F8b F8c F1 F7 F2 F4 shared-spu). Command in each copied
directory: `quartus_sh --flow compile ap_core` via `qrun.ps1`.

### Real device, 5CEBA4F23C8, reverb buffer (`E:\psx\ps1-r2-a4-buf`)

Synthesis succeeds (0 errors). **Fit fails** (exit 3):

- `Error (170011): Design contains 46686 blocks of type combinational node.
  However, the device contains only 36960 blocks.`
- `Error (170048): ... 308 RAM location(s) of type M10K block. However, the
  current design needs more than 308`
- Synthesis estimate 38,871 ALMs, 46,666 ALUTs, 49,708 registers,
  2,903,552 block bits, 65 DSP, 224 pins; fitter report 42,728 / 18,480 ALMs (231 %).

The doubled logic is a consequence of the RAM shortage, not of the core:
**when the inferred RAMs exceed the device's 308 M10K blocks, Quartus
synthesis implements the smaller RAMs as registers** (texture cache
19,843 registers, scratchpad 8,224, CD-ROM transfer buffer 4,105, I-cache
tags 2,333). Checked by synthesis-only experiments (`E:\psx\ps1-coreonly`,
`ps1-psxonly`, `ps1-tieA..D`, `ps1-pin1/2`, `ps1-buf-set`): the same
`PlayStation_core` text infers all RAMs as top (629,248 bits, 14,667
registers) and none of the input ties, unused outputs, logic-driven inputs
or the template's speed settings changes that; only adding the two
320x240x15 view buffers (286 M10K) does. The same design on the larger
5CEBA9 (below) infers every RAM.

### Information: same project on 5CEBA9F23C8 (`E:\psx\ps1-r2-a9-buf`)

Same package and pins except 16 unused `cram1` locations that Quartus 25.1
rejects on this die. Full compile successful (0 errors, 436 warnings).

| Resource | Needed | 5CEBA4 has | Gap |
|---|---:|---:|---:|
| ALMs (synthesis estimate) | 19,367 | 18,480 | +887 (+4.8 %) |
| ALMs needed after placement on A9 (A 22,549 − B 1,983 + C 345) | 20,912 | 18,480 | +2,432 (+13 %) |
| Dedicated registers (fit) | 18,053 (map 15,270) | 36,960 | — |
| M10K blocks | 373 | 308 | **+65** |
| DSP blocks | 65 | 66 | 1 spare |
| I/O pins | 224 | 224 | 0 spare |
| PLLs | 1 | 4 | — |

The A9 placement is sparse (2,932 LABs, packing difficulty "Low") and its
physical synthesis duplicates registers (R3000A 7,299 registers after fit
versus 5,216 in synthesis), so the 20,912 figure overstates a dense A4 fit;
the 19,367 synthesis estimate understates it. LABs on A4: 1,848.

Per entity after placement on A9 (ALMs needed / M10K):

| Entity | ALMs | M10K |
|---|---:|---:|
| `PlayStation_core` total | 19,015 | 84 |
| of it `R3000A` (GTE 6,018) | 10,846 | 1 |
| `SoundProcessingUnit` (shared DSP + reverb) | 2,753 | 64 (reverb buffer) |
| `GraphicProcessingUnit` (drawPoly 1,222) | 2,593 | 7 |
| `CDROM_controller` | 719 | 3 |
| `view_ram_ctrl` (two 320x240x15 buffers) | 128 | **286** (143 each) |
| `sdram128_burstn_adapter` | 546 | 0 |
| core_top glue, audio, APF | ~1,250 | 3 |

M10K by RAM: view buffers 286, reverb 64, I-cache 5, texture cache 5,
scratchpad 4, CD-ROM transfer 3, `inv_table` 2, APF datatable 2, audio FIFO 1,
GTE divide table 1. Timing on A9 (information only): `clk_50` setup slack
−0.676 ns, TNS −10.582; `dram_ctrl_clk` +6.394; `clk_74a` +5.946.

### Reverb in SPU RAM (`--reverb-in-spu-ram`)

- Real device (`E:\psx\ps1-r2-a4-spuram`): synthesis 38,838 ALMs estimate,
  46,643 ALUTs, 49,709 registers (the small RAMs again become registers), 2,379,264
  block bits, 65 DSP. Fit fails (exit 3): `Error (170011): Design contains 46663
  blocks of type combinational node ... only 36960`; M10K 297/308 after the
  conversion; fitter report 42,727 / 18,480 ALMs.
- Information, 5CEBA9 (`E:\psx\ps1-r2-a9-spuram`): full compile successful.
  ALMs needed 20,758 (A 22,283 − B 1,935 + C 410), synthesis estimate 19,819,
  registers 17,803 (map 15,271), **M10K 309** (one over 308: view buffers 286,
  `PlayStation_core` 20, others 3), DSP 65, pins 224. `clk_50` setup slack
  −0.454 ns, TNS −9.517 (information only).

### What dominates the gap

1. RAM: the two internal display buffers (286 of 308 blocks, roadmap P06).
   Without them the design needs 87 blocks; with them even the reverb
   variant is at the limit.
2. Logic: `PlayStation_core` alone needs ~19,000 ALMs after placement, over the
   device before any Pocket logic; the CPU/GTE is more than half of it
   (sflc area work, Q-L1-13). The Pocket-side additions (adapter, audio,
   top glue, APF) are about 1,900 ALMs.
3. DSP and pins are at their limits (65/66, 224/224).


## Uncommitted inputs (copied, SHA-256 pinned in the JSON)

| Path | SHA-256 | Owner |
|---|---|---|
| `Pocket/rtl/sram_ctrl.sv` | `c3604cc6…dbfbdb` | P02 replacement provider |
| `Pocket/rtl/ram_320x240x15_dp.sv` | `b0e0eec9…031069` | P02 replacement provider |
| `hdl/SDRAM/MIRLO64/sdr_ctrl.sv` | `cc1d5b18…51de46b` | MIRLO64 import, Apache-2.0 |
| `hdl/SDRAM/MIRLO64/sdr_phy.sv` | `84a2a161…457ee9` | MIRLO64 import, BSD-2 (LiteX) |
| `hdl/USB-JTAG/DE0-CV/vjtag_uart.v` | `aca8cb06…c6ae5` | USB-JTAG import |
| `hdl/USB-JTAG/DE0-CV/VirtualJTAG.v` | `e26ecf54…1e70de8` | USB-JTAG import |
| `hdl/USB-JTAG/DE0-CV/vjtag_uart.h` | `e2ccf5e6…901a71` | USB-JTAG import |

Full hashes are in `pocket_top_fixes.json` and each build's `ps1_build.json`.

## Not established

Booting, SDRAM behaviour on hardware, request ownership between the OR-combined
masters in core_top.v (CPU/GPU/SPU/loader), CDC of the loader path, timing
closure, audio on hardware, Quartus 18.1.1 compatibility.

## Lead follow-up measurements (2026-10-13, 5CEBA4F23C8, real pins, Quartus 25.1std)

All with sflc dca809a, source fixes incl. F8, shared SPU, option `single-view-buffer`
(one 320x240x15 display buffer: 143 instead of 286 RAM blocks; may tear; interim until
P06 moves display buffers to external memory). With one buffer Quartus infers the core's
RAMs again (block memory 1.27–1.79 Mbit).

| Run | QSF changes | Reverb | LABs needed / 1,848 | ALMs |
|---|---|---|---|---|
| r3-sv-buf | template (HIGH PERFORMANCE, physical synthesis on) | private buffer | 2,091 | 20,724 |
| r3-sv-spuram | template | SPU RAM | 2,090 | 20,746 |
| r4-area | AGGRESSIVE AREA, technique AREA, physical synthesis off | SPU RAM | 1,939 | 19,211 |
| r4-area-norvb | as r4-area | off (`--option reverb-off`) | **1,863** | 18,459 |

Fitter breakdown r3-sv-buf (failed-fit numbers overstate packing): PlayStation_core
18,527 ALMs (CPU+GTE 10,220, SPU 2,859, GPU 2,703, CDROM 672), SDRAM adapter 637,
audio out 233, APF bridge 219, pad/IO bridges ~200, JTAG hub 67, view_ram_ctrl 163.
The template's speed settings cost ~7 %; area mode plus reverb off leaves 15 LABs over.

## Hardware bring-up (Q-L1-16, 2026-10-13/14, Analogue Pocket, SCPH-5500, BIOS shell)

First boot to the BIOS CD-player shell with pad input: r13. Current best fit: r19b.

```
python3 -I tools/pocket/prepare_ps1_project.py --output Pocket/build/<new> \
  --reverb-in-spu-ram --option reverb-off --option no-jtag-debug \
  --option core-40mhz --option video-60hz --sdram-phase 270 --view-ram-2k5 \
  --qsf-profile area --seed 4
# area profile: AGGRESSIVE AREA, technique AREA, physical synthesis off,
# ALM_REGISTER_PACKING_EFFORT HIGH, MUX_RESTRUCTURE ON (about -1,800 ALMs).
# Checked: same QSF settings and sources as the r19b build directory.
```

r19b: 17,093 / 18,480 ALMs, 253 / 308 M10K, setup slack +0.97 ns (40 MHz core);
sound without reverb, two view buffers, 59.92 Hz video.

What was wrong, in the order found on hardware (debug overlays `debug-overlay`,
`debug-overlay-cpu` draw state bits at the top left of the picture):

1. 50 MHz core: setup slack -4.6 ns (GTE `running` -> CPU stall -> EX -> `gpr`).
   Symptoms changed per fit (CPU halt, I/O halt at PC 0xBF801004). `core-40mhz`
   scales the PLL by 4/5, keeps the 33.8688 MHz enable exact (DDS 10584/12500),
   and rescales the 1 s counter and SDRAM refresh.
2. SDRAM pads: the FAST_INPUT/OUTPUT/OUTPUT_ENABLE_REGISTER assignments MIRLO64
   uses for the same `sdr_phy` were missing; now always written. With sdr_phy's
   fixed read latency the pin bench (`tb_sdram128_burstn_pins.sv`, clocks made
   parametric) passes at 80 MHz only with the SDRAM clock at 270 degrees for
   6-9 ns data delay; MIRLO's own 125 MHz/180-degree setting passes for >= 7 ns.
3. Root cause of the garbage instructions: the APF loader strobe `ram1_word_wr`
   is one clk_74a cycle (13.5 ns). Upstream synchronised it into a 100 MHz
   clock; Q-L1-14 moved it to clk_50, where `synch_3` misses a third to a half
   of the strobes, so BIOS words were never written. Fixes C9-C12: 512 x 56
   dual-clock FIFO, drained when the adapter is `ready` and the core idle; the
   core sees ack only with the FIFO empty.
4. One view buffer: the display shows frames while they are drawn (the top
   layer flickers). Two inferred buffers made Analysis & Synthesis run out of its
   RAM estimate and leave 11 core RAMs as logic (40k ALMs). `--view-ram-2k5`
   builds each buffer as an explicit altsyncram, maximum_depth 2048 (2K x 5
   slices, 114 M10K instead of 144).
5. 40 MHz video ran at 47.95 Hz; the PSX vblank follows the VGA scan, so games
   ran 20% slow. `video-60hz` steps the scan every clock with 1274-clock lines:
   59.92 Hz, video clock 40 MHz.

Known open: reverb on does not route at 98% (r21); the SRAM loader path
(`ram_word_wr_hold_r`) still samples `ram1_word_data` about 3 core clocks late;
50 MHz timing.

### Sound-on runaway (2026-10-14): fixes T11, T12

Every sound-on build ran away during the BIOS on hardware (no halt, PC
0x80A81C2x, black picture); sound-off r13 booted. The full-chain simulation
(`Pocket/sim/fullchain/`, `Pocket/sim/run_pocket_sim.py`: the prepared core_top
with the loader FIFOs, the SDRAM adapter chain, an SDRAM scoreboard and an APF
host model) reproduced the PC exactly. Cause: core.sflp strobed CPU SDRAM
commands without looking at `sdram_ack`; one that arrived while an SPU/GPU
command was in flight was dropped by the adapter, and the next ack handed the
other command's completion and stale data to the CPU. T12a-T12f hold the CPU
command while a GPU/SPU command is in flight and gate the CPU's ack the same
way; simulated 14 s: SCE logo and BIOS shell, 0 dropped, 0 mismatches. T11
(a CPU strobe owns the cycle) stays; it was not the cause. The old boot bench
(`Pocket/sim/tb_psx_boot.sv`) served SPU RAM separately and gave the CPU
priority, so it could not show either.

```
python3 -I Pocket/sim/run_pocket_sim.py build Pocket/build/<prepared dir>
python3 -I Pocket/sim/run_pocket_sim.py run Pocket/build/<prepared dir> <scph5500.bin> \
  Pocket/build/<prepared dir>/out --cycles 560000000     # ~45 min, PPM frames in out/
```
