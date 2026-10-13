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
python3 -I tools/sflc/cosim.py --reference-dir <scratch>/ci2/sfl2vl-probe-out  # 9 PASS (p01 p03 p04 p09 p11 p12 p14 p15 p16), exit 0
python3 -I tools/sflc/cosim.py --reference-dir <scratch>/ci1/sfl2vl-probe-out  # same 9 PASS, exit 0
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


## Remaining gap and next candidates

Gap after change 1: the SPU-off core alone fits at 95 % of the ALMs. The
full Pocket build still needs the Pocket top (~1.5k ALMs) and the time-shared
SPU (~2k ALMs), i.e. roughly 3k more ALMs must go. Candidates, ranked by
expected saving (none measured yet):

1. **Bank words with two non-exclusive ports (~2k ALUTs).** GTE `d` (RTP
   states vs MFC2/MTC2 on `rd_reg`) and R3000A `gpr` (EX vs MEM write-back)
   keep two ports, which costs about one ALUT per bit per word (~1k each).
   Removing it needs either a deeper exclusivity proof (value-range analysis,
   e.g. `rtp_v` in 0..2 so `s_fSX+12` never equals a MTC2 `rd_reg` target is
   not even true) or a documented semantic choice (single port with
   assertions). The R3000A case is genuinely parallel, so this is a lead
   decision, not a compiler-local one.
2. **SPU-off remnant (1,608 ALUTs, 2,695 registers)** disappears when the
   `DigitalSignalProcessor` is swapped for the Q-L1-12 engine; no sflc work.
3. **GTE datapaths (7.2k self ALUTs)**: per-operation 44/64-bit adders and the
   18-term `set_MAC*`/`s_MAC*` selectors are source structure (one datapath
   per op, 48 DSP). A measurement per op (comment out ops in a scratch copy)
   would show whether any lowering detail (context-width widening of `+`,
   `sext` temporaries) adds cost over a hand-written adder; no evidence yet.
4. **Read muxes of banks**: every distinct dynamic index expression text of a
   bank is a separate N:1 mux (`d[(s_fSX)+(5'd12)]`, `d[(s_fSY)+(5'd12)]`,
   ...). Sharing them needs value equality, not text equality; small (~350
   ALUTs per 32x32 mux) and source-inherent.
5. **Non-bank memories with several dynamic writers** (`CommandBuffer`,
   `Result`, `Transfer`) already use one OR-selected port; their cost is in
   the read muxes. Note the semantic asymmetry: these would also lose
   simultaneous distinct-word writes, exactly the case upstream relies on for
   `gpr`. No such pattern was found in them, but it was not proven absent.

Not done: no native per-entity report exists for comparison, so the
remaining "sflc vs native" gap per module is unknown; the author's 17,060
ALMs include the full SPU and the Pocket top.

