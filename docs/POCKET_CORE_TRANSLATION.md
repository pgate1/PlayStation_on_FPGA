# PS1 core translation closure (Q-L1-11)

**Result (2026-10-13):** the full `PlayStation_core` hierarchy translates with
`sflc.py --hierarchy --register-banks` (1,702,323-byte SystemVerilog) and
elaborates in Icarus with the 16 repository Verilog leaves plus the restored
`mul_u16.v`. This is structural evidence only: not native-sfl2vl equivalence,
not synthesis, fit or timing, and not behaviour on hardware.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -I tools/pocket/prepare_core_sources.py \
    Pocket/build/core-src --check
# PREPARED 59 files, fixes F3 F6 F6b F5 F1 F7 F2 F4 -> .../core-src
# translated PlayStation_core.sv: 1702323 bytes
# ELABORATED PlayStation_core with 16 Verilog leaves (structural only; ...)
```

Every repository-root module except `view_ram_ctrl` also translates on its own
from the prepared sources. `view_ram_ctrl` is board-level (used only by the
`DE0-CV`, `DE2-115` and `Pocket` `core.sflp` tops), and its RAM
`ram_320x240x15_dp` is a private upstream module (see `POCKET_P00_TOOLCHAIN.md`).
It is outside `PlayStation_core` and belongs to the Pocket top-level owner.

## Why repairs were needed

Upstream (`pgate1/PlayStation_on_FPGA`) is a partial snapshot of the author's
tree. The root Makefile lists `ram_320x240x15_dp`, `view_ram_ctrl_one` and
`pseudo_cdrom_data`, which have never been published. Several recent upstream
commits renamed or removed declarations without updating every use. Whether the
author's own `sflp`/`sfl2vl` tolerates these, or the published files differ
from the ones built, cannot be determined locally.

Upstream files are **never edited in place**. `tools/pocket/prepare_core_sources.py`
copies the root `*.sflp`/`*.v` and `demo/` into a new directory, checks each
patched file's pinned SHA-256, applies `Pocket/source_fixes/fixes.json` (each fix
must match exactly once, and CRLF and latin-1 bytes are preserved), and writes
`core_sources.json` with the hash of every prepared file. An upstream merge that
changes a patched file makes the preparer fail until the fix is re-reviewed.

## Repair ledger

Class A means semantics-neutral (a duplicate, an unread leftover, or a missing
declaration whose width is fixed by its use). Class B means a reconstruction that
needs judgement; re-check these first if behaviour differs.

| ID | File | Class | Change | Evidence |
|---|---|---|---|---|
| F1 | PlayStation_core | A | drop second identical `output file_adrs<32>` | added twice by d2bf610 |
| F2 | R3000A | A | comment out `cache_hit_reg := 0b00;` | only reference anywhere; 32e1b76; never read |
| F3 | DMA_CDR | A | comment out `dbg32 = dbg32_reg;` | 3fa770f renamed to dbg/dbg_reg; core reads `cdr.dbg32` from CDROM_controller |
| F4 | drawRect | A | add `sel under640;` | d699e96 added the use; drawPoly:321 declares the same 1-bit sel |
| F5 | GraphicProcessingUnit | B | make `texture_full` forwarding a no-op | `poly.texture_full` has never existed in any published drawPoly; core calls it every cycle |
| F6 | DMA_SPU | B | restore `declare mul_u16`, `mul_u16 size_mul`, 32-bit `bcr`; add `mul_u16.v` | 3fa770f removed them but kept `size_mul.con(bcr<31:16>, bcr<15:0>)`; `mul_u16.v` byte-identical from 2526d25^ |
| F7 | PlayStation_core | B | `else : read_io_wait.do();` becomes `generate read_io_wait.do();` | only bare stage-task call in all sources (since 2021); siblings use generate; without it the CPU read is never acked |

## Compiler additions (sflc)

- String constants: `"SCEI"` is an 8-bit-per-character constant, first
  character in the most significant byte (CDROM_controller GetID slices
  `str<31:24>` into `Result[4]`). Empty strings and escapes are rejected.
- Empty call of a local `instrout` that has arguments (`mem_read_req();` in
  SoundProcessingUnit) activates the terminal without driving its formals.
  `instrself` and child `instrin` keep the exact argument-count rule (tests 05/11).
- Test 18 (`tests/core_gaps.sflp`, `tb_core_gaps.sv`): `PASS core_gaps
  checks=1000`; a byte-reversed string encoding is caught. Full suite: 18 OK.

## First Quartus results (2026-10-13, ristisana, Quartus 25.1std Lite, 5CEBA4F23C8)

Synthesis only (`quartus_map`) of the prepared core, then a fit with all pins
virtual. Projects: `E:\psx\core-map`, `core-map-spuoff`, `core-fit-spuoff`.

| Run | Comb. ALUTs | Registers | Block mem bits | DSP | ALM estimate / fit |
|---|---|---|---|---|---|
| Full `PlayStation_core` (switches as pins) | 63,399 | 24,766 | 629,248 | 122 | ~37,874 (map estimate) |
| SPU switches tied off as upstream Pocket does | 31,530 | 14,763 | 104,960 | 59 | ~19,749 (map); **fit fails: 2,022 LABs needed, 1,848 exist** |
| Upstream author's native Pocket fit (18.1.1, whole top) | — | 13,386 | 2,406,963 | 58 | 17,060 / 18,480 ALMs |

Largest blocks, full run (comb. ALUTs / registers / DSP): 24 x `dsp_ch` ~29,800 /
~11,500 / 72; `R3000A` 15,770 (GTE 9,292 of it) / 5,206 / 42; `GraphicProcessingUnit`
4,419 / 2,292 / 7; `PAD_controller` 5,565 / 2,197 / 0; `reverb` 1,204 / 999 / 3
plus 512 Kbit. With the SPU off the DSP count matches native (59 vs 58), but the
core alone already overflows the device without any Pocket top, while the native
build fit everything at 92%. Two consequences:

1. Sound requires replacing the 24 parallel voices (Q-L1-12, time-shared engine).
2. sflc-generated logic is larger than native by roughly 20% or more; this needs
   its own audit (READY packet Q-L1-13) before a full Pocket build can fit.

## Not established

- `--register-banks` is still the experimental mode with the retained native
  p27 mismatch; GTE needs it. Its use here is unqualified.
- No simulation of the core yet (BIOS boot), no Quartus synthesis, no
  resource estimate for 5CEBA4F23C8, no Pocket top integration.
- Next: Quartus synthesis-only run of the elaborated core on the shared
  Windows host for a first ALM/RAM estimate, then a BIOS-boot simulation.
