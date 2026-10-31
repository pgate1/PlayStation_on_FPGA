# Source-defect evidence inventory (Q-L1-04)

Read-only inventory of compiler-visible defects in the original SFL sources.
No source or compiler file was changed. Nothing here says what the hardware
was intended to do; each entry only records what the source text and the
local compiler report.

Compiler: `tools/sflc/sflc.py` (Python 3.12, no native SFL tools). Each case
was run with default defines and with `-D DEMO`. Results were identical in
both contexts: the `DEMO` define does not change any of these five errors.

Run from the repository root. Use `PYTHONDONTWRITEBYTECODE=1` and `LC_ALL=C`
because the sources are CRLF/latin-1. `-a` is needed because grep treats some
sources as binary.

## Evidence table

| # | Symbol | Source lines (exact text) | Other defining or using lines | Compiler result (default and `-D DEMO`) | Classification |
|---|---|---|---|---|---|
| 1 | `texture_full` | `GraphicProcessingUnit.sflp:110` `instrin texture_full;`<br>`GraphicProcessingUnit.sflp:567` `instruct texture_full if(^dispW) poly.texture_full();` | `drawPoly.sflp` has no `texture_full` port. `PlayStation_core.sflp:557` `reg_wr cdr_dma_count<4>, f_texture_full, f_view_half;`; `:558`, `:560` commented; `:561` `gpu.texture_full();` (uncommented) | `GraphicProcessingUnit.sflp: NameError: unknown port poly.texture_full`, exit 1 | Confirmed: call to a port not in the callee's interface |
| 2 | `under640` | `drawRect.sflp:85` `under640 = (vx1-0b01010000000)<10>; // x < 640`<br>`drawRect.sflp:112` `if(under640 & sw_view_half_width){` | `drawPoly.sflp:321` `sel under640;` and `:324` assignment (drawPoly declares it locally); `drawPoly.sflp:302` commented use | `drawRect.sflp: NameError: undeclared under640`, exit 1 | Confirmed: `drawRect` has no declaration (`sel`/`reg`/port) |
| 3 | `dbg32` | `DMA_CDR.sflp:44` `dbg32 = dbg32_reg;` | `DMA_CDR.sflp` declares `output dbg<32>;`, `reg_wr dbg_reg<32>;`, `output dbg_sum<32>;` (lines 33–35), so neither `dbg32` nor `dbg32_reg` is declared. `PlayStation_core.sflp:145` `output dbg32<32>;`; `:146` `//reg_wr dbg32_reg<32>;` (commented); `:173` `dbg32 = cdr.dbg32;//dbg32_reg;dma_CDR.dbg32;cpu.dbg32;` | `DMA_CDR.sflp: NameError: undeclared dbg32`, exit 1 | Confirmed: `DMA_CDR` uses undeclared names; the top-level `cdr.dbg32` reference does not resolve it |
| 4 | `size_mul` | `DMA_SPU.sflp:55` `dma_size = size_mul.con(bcr<31:16>, bcr<15:0>).dout<30:0> \|\| 0b0;` | `DMA_SPU.sflp:52–54` commented original (`// uint32 size = ...`). `MDEC.sflp:65` `dma_size = 64;//size_mul.con(bcr<31:16>, bcr<15:0>).dout;`. No `size_mul` module exists in the repo. | `DMA_SPU.sflp: NameError: undeclared size_mul`, exit 1 | Unresolved: the instance is used but no module of that name is in the repo; it may be an external or missing module. Check the module name and whether it is a required build input. |
| 5 | `file_adrs` | `PlayStation_core.sflp:114` `output file_adrs<32>;`<br>`PlayStation_core.sflp:116` `output file_adrs<32>;` | `PlayStation_core.sflp:115` `instrout file_read_req, file_preload;`; `:117` `instrin file_ack;`; `:369` `file_adrs = cdr.file_adrs;` | `PlayStation_core.sflp: ValueError: duplicate interface port file_adrs`, exit 1 | Confirmed: same port declared twice in one interface |
| 6 | `DEMO` | `PlayStation_core.sflp:6` `//#define DEMO` (commented, so `DEMO` is undefined by default) | `#ifdef DEMO` blocks at `:21`, `:121`, `:273`, `:425`, `:543` | Default: no `DEMO`. With `-D DEMO`: same five errors above (see table). | Context only, not a defect by itself. Recorded because `DEMO` changes which blocks are compiled. |

Lines 1–5 are the errors reported in `docs/POCKET_HANDOFF_2026-10-12.md`.
Line 4 notes a missing module, not an error in the grep-visible text.

## Reproduce

```sh
cd /Users/dst/Documents/koodi/PlayStation_on_FPGA-master
export PYTHONDONTWRITEBYTECODE=1 LC_ALL=C

# compiler errors (expect exit 1 each; default defines)
for f in GraphicProcessingUnit DMA_SPU drawRect DMA_CDR PlayStation_core; do
  python3 tools/sflc/sflc.py $f.sflp >/dev/null 2>&1; echo "$f exit=$?"
done

# same with DEMO defined (expect the same messages)
for f in GraphicProcessingUnit DMA_SPU drawRect DMA_CDR PlayStation_core; do
  python3 tools/sflc/sflc.py -D DEMO $f.sflp >/dev/null 2>&1; echo "$f -D DEMO exit=$?"
done

# source lines
grep -an 'texture_full' GraphicProcessingUnit.sflp drawPoly.sflp PlayStation_core.sflp
grep -an 'under640' drawRect.sflp drawPoly.sflp
grep -an 'dbg32' DMA_CDR.sflp PlayStation_core.sflp
grep -an 'size_mul' DMA_SPU.sflp MDEC.sflp
grep -an 'file_adrs' PlayStation_core.sflp
grep -an 'DEMO' PlayStation_core.sflp
```

The `-D DEMO` loop was run once in this session. The output was the same
error text as the default run for every file.

## Not checked here

- Whether the five errors are the first errors or only the first one the
  compiler reports for each file.
- Whether `size_mul`, `dbg32`, or `under640` should be declared locally, or
  imported from a module not in this repository.
- Behavior under the native SFL toolchain, which is not installed.
- Any fix. These entries are inputs to a later decision, not corrections.
