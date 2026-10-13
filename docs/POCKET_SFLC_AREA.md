# sflc area audit (Q-L1-13)

Goal: make `tools/sflc/sflc.py` emit smaller logic so the SPU-off
`PlayStation_core` fits the Pocket's 5CEBA4F23C8 (18,480 ALMs, 1,848 LABs).
Baseline (2026-10-13, Quartus 25.1std Lite, `E:\psx\core-map-spuoff`):
31,530 comb. ALUTs, 14,763 registers, 59 DSP, ~19,749 ALMs estimated; the
virtual-pin fit failed at 2,022/1,848 LABs. See `POCKET_CORE_TRANSLATION.md`.

All numbers below are synthesis (`quartus_map`) results unless marked FIT.
Nothing here is native-sfl2vl equivalence or hardware acceptance.

## Method

- `tools/sflc/area/equiv_sim.py`: compiles the old (`git HEAD`) and new
  translation of one module from the same prepared sources, drives both with
  identical random stimulus in Icarus (sparse 1-bit controls, periodic reset)
  and requires byte-identical per-cycle traces of every output plus optional
  internal probes (`--probe mem=depth`). Unknown bits must match too.
- `tools/sflc/area/qmap.py`: builds a one-entity Quartus project from the
  translated core and the Verilog leaves, uploads it to `E:\psx\area-<name>`,
  starts it only through `E:\fpga-shared\qrun.ps1` (session `pocket-psx`), and
  parses the per-entity table of the map report. Module-level numbers differ
  slightly from the in-core numbers (no constant propagation from the parent).
- Micro-experiment `exp1` (32 words x 32 bits, 3 dynamic writers, clear):
  per-word guarded OR of all writers 1,504 ALUTs; shared selected port with
  `(sel ? d : 0)` data 454; shared port written as `if (sel) w <= d; else if
  (clr) w <= 0;` 352 (the 32:1 read mux alone is ~350). Identical guard text
  duplicated 32 times cost the same as one wire (Quartus merges it).

## Finding 1 (largest): register-bank memories expanded per word and per writer

`mem` arrays with constant-index writers (`--register-banks`: GTE `d`/`c`,
R3000A `gpr`/`cpr0`, PAD `data_buf[256]`, CDROM `Param`/`Transfer_head`)
were lowered as one guarded-OR per word over *every* writer, each dynamic
writer carrying its own address decode and full data path into every word.
For GTE `d` that is 32 words x 32 bits x ~9 terms; for PAD `data_buf` 256 x 8
x ~5 terms. This alone explains most of the PAD_controller's 5,508 ALUTs and
a large share of the GTE's 8,017.

Upstream relies on parallel distinct-word writes (R3000A `stage_MEM` writes
`gpr[mem_rt]` while EX writes `gpr[set_gpr_index]`, guarded only by
`mem_rt != ex_gpr_index`), so a single shared write port per memory is NOT
acceptable: an experiment with one shared port mismatched the old lowering
in random co-simulation at GTE cycle 107 (`d[4]`,`d[16]` vs `d[20]`) and
R3000A cycle 1720 (`gpr[19]`,`gpr[20]` vs `gpr[23]`). That variant was
discarded.

### Change 1: shared ports only where equivalent by construction

Dynamic-index writers of a bank are grouped into shared selected ports
(`__sfl_wport_<mem>_<k>_{en,a,d}`), each port being the usual OR-selected
address/data of its members, and every word keeps
`(port_en && port_a == i) ? port_d` as one guarded-OR term next to its
constant-index writers:

1. Writers with the same address expression text share a port:
   `(g1 && A==i ? v1 : 0) | (g2 && A==i ? v2 : 0)` equals
   `A==i ? ((g1 ? v1 : 0) | (g2 ? v2 : 0)) : 0` for every word.
2. Groups whose guards are provably never active together share a port: at
   most one group drives it in any cycle, so the OR-selected address and data
   are that group's. The proof is syntactic and sound: after expanding local
   `instrself`/`instrout` guards into their activation guards (bounded DNF),
   two conjunctions are exclusive when one contains `X` and the other `!(X)`,
   or both compare the same expression text with different constants
   (`state == 2` vs `state == 5`, `((CtrlReg[13])==(1'b0))` vs `...(1'b1)`).
   Anything unknown is treated as not exclusive.
3. Constant-zero writers (parallel clears) only extend the enable; a word with
   one remaining nonzero writer is emitted as `if (g) w <= v; else if (en) w
   <= '0;` (exp1 form, same function).
4. Writers of the same value text are merged everywhere (`mux`):
   `(g1 ? v : 0) | (g2 ? v : 0)` is `((g1 || g2) ? v : 0)`.

Resulting ports: GTE `d` 2 (fSX/fSY/fSZ from exclusive RTP states merged;
MFC2/MTC2 on `rd_reg` merged), `c` 1, R3000A `gpr` 2 (EX and MEM stay
separate, as required), `cpr0` 1, PAD `data_buf` 1, CDROM `Param` 1,
`Transfer_head` 1.

Evidence:

- `tools/sflc/tests/bank_ports.sflp` + `tb_bank_ports.sv` (test 19): an
  independent per-word reference model, 3,000 random cycles, 24,000 word
  checks, >=170 cycles with simultaneous distinct-word writes from different
  ports; asserts `share 2 selected port(s)`. Mutations that must fail and do:
  `Gen.exclusive` forced true (everything shares one port) and `Gen.is_zero`
  forced true (nonzero data dropped).
- Old-vs-new random co-simulation (`equiv_sim.py`, seed 1, probes on every
  bank): PASS GeometryTransformationEngine 30,000 cycles (d, c), PAD_controller
  40,000 (data_buf[256]), R3000A 20,000 (gpr, cpr0), CDROM_controller 30,000
  (Param, Transfer_head, Result), GraphicProcessingUnit 20,000
  (CommandBuffer), drawPoly, DMA_GPU, MDEC 20,000-30,000, PlayStation_core
  6,000 (see Results for exact lines).
- `run_tests.py`: 19 OK; `test_instance_array_boundaries.py`: OK;
  `cosim.py --reference-dir ci1/ci2 sfl2vl-probe-out`: all local references
  pass; `prepare_core_sources.py --check`: translates and elaborates.

### Results

Per-entity comb. ALUTs (self), SPU-off core synthesis, Quartus 25.1std Lite:

| Entity | Baseline (919b144) | Change 1 (bank ports, `core-new2`) | Change 1+2 (`core-new3`, committed `104f91f`) |
|---|---|---|---|
| psx_pocket_est total ALUTs | 31,530 | 26,158 | **26,007** (-17.5 %) |
| registers | 14,763 | 14,776 | 14,757 |
| DSP | 59 | 59 | 59 |
| ALM estimate (map) | ~19,749 | 17,098 | 16,891 |
| FIT (virtual pins) | fails: 2,022/1,848 LABs | **Successful: 17,594 / 18,480 ALMs (95 %)**, 15,264 registers | **Successful: 17,406 / 18,480 ALMs (94 %)**, 15,307 registers, 59/66 DSP |
| PAD_controller self | 5,508 | 1,827 | 1,823 |
| GeometryTransformationEngine self | 8,017 | 7,247 | 7,325 |
| R3000A self | 6,030 | 5,033 | 4,921 |
| drawPoly self | 2,057 | 2,025 | 2,021 |
| PlayStation_core self | 1,645 | 1,662 | 1,673 |
| GraphicProcessingUnit self | 1,417 | 1,450 | 1,490 |
| CDROM_controller self | 1,159 | 1,167 | 1,157 |
| DigitalSignalProcessor self (SPU-off remnant) | — | 1,608 (2,695 regs incl. 24 x 109 voice regs) | 59_ |

Module-level (`qmap.py`, entity as top): GeometryTransformationEngine 8,340 ->
7,381 self ALUTs (`gte-base` -> `gte-new2`), 7,325_MOD; PAD_controller 1,803
(`pad-new2`); R3000A 5,146 self (`cpu-new2`). Jobs: `E:\psx\area-{exp1,gte-base,
gte-new2,core-new2,pad-new2,cpu-new2,core-new3,gte-new3}`, all `DONE exit=0`.

Registers did not change (same source registers; banks were already
registers). The tie-off removes the voice datapaths but not their registers;
those go away with the Q-L1-12 time-shared engine.

Exact verification commands (all exit 0 unless stated):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -I tools/sflc/tests/run_tests.py        # Ran 19 tests ... OK
python3 -I tools/sflc/tests/test_instance_array_boundaries.py             # OK
python3 -I tools/sflc/cosim.py --reference-dir <scratch>/ci2/sfl2vl-probe-out  # 9 PASS (p01 p03 p04 p09 p11 p12 p14 p15 p16);
python3 -I tools/sflc/cosim.py --reference-dir <scratch>/ci1/sfl2vl-probe-out  # same 9 PASS; both runners then exit 1 with
    # "p22_widths: missing reference" because the p22-p26/bsr_s16 reference files are not in the local
    # ci1/ci2 copies (the runner has no case filter). No mismatch was reported.
python3 -I tools/pocket/prepare_core_sources.py <new_dir> --check          # ELABORATED PlayStation_core with 16 Verilog leaves
python3 -I tools/sflc/area/equiv_sim.py --module <M> --old base/PlayStation_core.sv \
    --new new/PlayStation_core.sv --leaf-dir base --cycles N [--probe mem=depth]
# PASS equiv GeometryTransformationEngine cycles=30000 seed=1 compared=68
# PASS equiv PAD_controller cycles=40000 seed=1 compared=264
# PASS equiv R3000A cycles=20000 seed=1 compared=78
# PASS equiv CDROM_controller cycles=30000 seed=1 compared=44
# PASS equiv GraphicProcessingUnit cycles=20000 seed=1 compared=41
# PASS equiv drawPoly cycles=20000 seed=1 compared=15
# PASS equiv DMA_GPU cycles=30000 seed=1 compared=12
# PASS equiv MDEC cycles=30000 seed=1 compared=11
# PASS equiv PlayStation_core cycles=6000 seed=1 compared=51
```

Sequential native references (p17-p28) are not present locally, so
`cosim_sequential.py` was not run; the combinational set above is the only
native oracle available on this machine.


## Round 2 (lead decision 2026-10-13: continue)

Lead's new baseline with compiler `104f91f`, time-shared SPU and full sound
(`prepare_core_sources.py --shared-spu`, virtual pins): 1,877 LABs / 1,848,
18,481 ALMs, 64/66 DSP; with `--reverb-in-spu-ram` 1,893 LABs, 18,629 ALMs.
Pocket top (~1.5k ALMs) still to come; target 2,000-2,500 ALMs more.

### (1) Two-port banks: no sound merge exists; the floor is measured

- GTE `d`: port 0 (`set_fSX/fSY/fSZ`, RTP states) and port 1 (MFC2/MTC2 on
  `rd_reg`) are exclusive only because the CPU stalls on `gte.running`
  (R3000A line 254) — a cross-module invariant the GTE source does not
  encode, so no in-module proof is possible. Value ranges do not help either:
  `rtp_v` is declared `reg rtp_v<5>` and is incremented, so its range is the
  full 0..31 without a state-machine invariant.
- R3000A `gpr`: EX (`set_gpr`) and MEM (`gpr[mem_rt]`, guarded by
  `mem_rt != ex_gpr_index`) genuinely write different words in the same
  cycle; two ports are required.
- exp2 (`E:\psx\area-exp2`, 32x32 bank, two ports + clear, read mux included):
  per-word OR 1,472 ALUTs; priority triple with shared `d0|d1` 1,440;
  nested 1,409; `if (s0) w <= d0 | (s1 ? d1 : 0); else if (s1) w <= d1;`
  1,376; pre-masked shared data 1,440. All exact forms cost ~1 ALUT per bit
  per word (~1,050 write logic + ~350 read mux): the floor for two write
  ports with asynchronous constant-index reads. Only a semantic choice
  (single port with assertions, relying on the CPU stall) would remove
  ~1k ALUTs across `d` and `gpr`; not taken (lead rule: prove any merge).

### Change 3: two-writer words as a priority pair (exact, small)

Tried and withdrawn. A word with exactly two nonzero writers was emitted as
`if (g0) w <= v0 | (g1 ? v1 : 0); else if (g1) w <= v1; [else if (en) w <= 0]`
(exp2 `b2_orin`, same function). It passed the suite and old-vs-new
co-simulation (seed 2: GTE, PAD, R3000A, CDROM, GPU, PlayStation_core), but
at core level it moved logic into full-ALM 6-input functions: SPU-off map
`core-new5` (pair + CSE) 25,916 ALUTs, 6-input functions 6,659 (was 5,749),
ALM estimate 17,309 versus `core-new6` (CSE only) 25,856 ALUTs, estimate
16,797. The fitter's own ALM count moves with packing at this fill level
(17,406 / 17,891 / 17,744 for new3 / new5 / new6), so the map estimate and
the function-size histogram are the comparable figures. Withdrawn in
`dca809a`; the plain guarded OR stays.

### Change 4: common-subexpression wires

Identical sliced/extended expressions now share one `__sfl_expr_N` wire
(103 duplicate texts in the GTE alone; `d[rd_reg]` read three times in
MFC2). Pure expressions, exact by construction; Quartus merges most of these
itself (exp1). SPU-off core `core-new6` (committed state `dca809a`, the
translation is byte-identical to new6 up to the order of the port wires):
25,856 ALUTs (-151 vs `core-new3`), 14,757 regs, 58 DSP (one redundant GTE
multiplier merged), ALM estimate 16,797 (-94), FIT successful 17,744 /
18,480. Old-vs-new co-simulation seed 4: PASS GeometryTransformationEngine
30,000, PAD_controller 30,000, R3000A 20,000, CDROM_controller 20,000,
GraphicProcessingUnit 20,000, drawPoly 20,000, PlayStation_core 6,000.

### (3a) Source-level hotspot found: PAD_controller `data_buf[parp]` in state st2

The largest remaining single structure in the design is the 256:1 x 8-bit
read mux `data_buf[parp]` (Quartus baseline 1,360 LEs), used only in
`WriteData_stg` state `st2`. `st2` is entered solely from `st1`'s
`padst==1` branch, which assigns `parp := 1` on the same edge, and nothing
writes `parp` in `st2`; so there `data_buf[parp]` is `data_buf[1]`. A
compiler cannot prove this without state-machine invariants, but a source
fix can use it. Evidence with a scratch copy (not committed; upstream and
`Pocket/source_fixes` are owned elsewhere): `equiv_sim.py` old (unpatched)
vs patched PAD_controller, 60,000 cycles, seed 3, probes `data_buf[256]`,
`parp`, `bufcount`: PASS (compared=266). Module-level synthesis (`pad-new5` vs `pad-fix`, same compiler):
PAD_controller self 1,770 -> 342 ALUTs, registers 2,151 -> 167, ALM
estimate 1,724 -> 294. With the only full-index read gone, words 8..255 of
`data_buf` are write-only (ReadData reads `data_buf[parp<2:0>]` and returns
constants for the memory-card bytes), so Quartus removes them. Expected
core-level saving about 1,400 ALMs — the single largest item available, and
it is a source fix (`Pocket/source_fixes`, class B: relies on the st1->st2
invariant), not a compiler change. Recommended as fix F8 for the lead.

### (3) Debug outputs kept alive by the estimate wrappers

The upstream Pocket top (`Pocket/core.sflp`) reads only `halt_code`,
`halt_part`, `dbg`, `mdec_waiting`, `gpu_drawing`, `sio_waiting`,
`kernel_ok`. Every estimate so far exposed all core outputs as (virtual)
pins, so `dbg2`, `dbg_cpu`, `dbg_cdr`, `dbg_gpu`, `dbg16`, `dbg32`,
`dbg_pad`, `pc_out`, `opcode_out`, `disp_env`, `vraming`, `dma_running`
and the logic/registers feeding them were kept. Wrappers that leave them
unconnected (`psx_pocket_est_nodbg.sv` SPU-off; `psx_full_nodbg.sv` with
`--shared-spu`) measure the realistic configuration:
SPU-off `core-nodbg`: 25,958 ALUTs, 14,732 regs, ALM est 16,758, FIT 17,587
/ 18,480 (vs 26,007 / 17,406 with every output exposed) — no saving; the
voice/debug registers stay because they feed `halt_code`/`dbg`, which the
top does read. Full sound `full3-nodbg` (`--shared-spu`, compiler 104f91f):
27,596 ALUTs, 14,642 regs, 64 DSP, ALM est 17,924, FIT FAILED at 18,389 /
18,480 (100 %), consistent with the lead's 18,481. Conclusion: the debug
ports are not the artefact; nothing to gain here.

## Remaining gap and next candidates (after round 2)

Full-sound build (`--shared-spu`, virtual pins) with the final compiler
`dca809a`: `full8`: 27,506 comb. ALUTs, 14,667 registers,
63 DSP, 629,248 memory bits, ALM estimate 18,081; FIT FAILED at 18,575 /
18,480 ALMs (101 %) — unchanged within noise from the lead's 18,481 with
`104f91f` (round 2 compiler changes are worth ~-100 ALUTs at full-sound
level; the DSP count dropped 64 -> 63). The Pocket top (~1.5k ALMs) is still to come.

Compiler-side exact lowering is now at the floor this source structure
allows: the remaining logic is register-file read muxes, per-op GTE
datapaths and result selectors that native sfl2vl must also build. Ranked
candidates, with the evidence behind each estimate:

1. **Source fix F8, PAD_controller st2 `data_buf[parp]` -> `data_buf[1]`
   (~1,400 ALMs).** Exact by the st1->st2 invariant; co-simulation PASS
   60,000 cycles with `data_buf`/`parp`/`bufcount` probes; module synthesis
   1,770 -> 342 ALUTs, 2,151 -> 167 registers. Owner: source_fixes.
2. **GTE `d` single write port (~500 ALMs).** Needs the cross-module
   invariant "CPU stalls on gte.running" (R3000A:254); would be a documented
   semantic choice checked by `--assertions`, not a proof. Lead decision.
3. **Reverb placement** (lead's options, outside sflc).
4. Nothing else above ~100 ALMs was found by measurement; the 2-port
   `gpr`/`d` floor (exp2), debug-port tie-off (core-nodbg, full3-nodbg:
   no change) and the priority-pair form (withdrawn) were all measured.

Per-entity self ALUTs with `dca809a`, SPU-off (`core-new6`): R3000A 4,945,
GTE 7,224, PAD 1,823, top 1,658; full sound adds the shared SPU/reverb
(~3.5k ALUTs incl. reverb 1,152).
