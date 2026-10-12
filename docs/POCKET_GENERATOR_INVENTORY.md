# Generator and source inventory (Q-L1-07)

Read-only inventory of `par`, `any`, `alt` and `join` generator sites in the
44 original SFL+ sources. No source was edited and no compiler, Quartus or
synthesis tool was run except the `tools/sflc/sflc.py` probes listed below.
Nothing here is a fix proposal; the compiler owner decides on those.

Scope: the 44 files in the scratch list, excluding `tools/sflc/tests`,
`tools/sflc/probe` and build caches. `Pocket/core.sflp` is in the list
(uncommitted, owned by another provider) and was read from disk; it contains
no generator sites.

## Method

- Script: scratchpad `gen_inventory.py` (read-only, stdlib). Comments are
  masked to spaces first, then the generator header
  `kw(var = start; var < end; var++)` is matched and the body is brace-matched.
- Command: `PYTHONDONTWRITEBYTECODE=1 python3 -I gen_inventory.py <scratch>`,
  exit 0. Output: `gen_inventory.tsv` (36 data rows), `gen_headers_raw.txt`,
  `gen_kw_all.txt`.
- Nested generators: none. Loose-only headers (keyword followed by `(` and an
  assignment but not matching the strict header): none.
- Body categories are counted by pattern (`:=`, `]:=`, `case`, `state`,
  `instruct`, instance calls). The "kind" column below is my reading of each
  body and was checked by hand against the source lines.

Keyword counts: par 23, any 5, alt 2, join 6. Total 36.

## Site table

Iters = end − start (literal bounds; all 36 are literal).
Body: A = register/wire assignment, M = memory write, I = instance call or
port reference, S = selector/priority bit assignment.

| File | Line | Kw | Bounds | Iters | Body | Notes |
|---|---|---|---|---|---|---|
| CDROM_controller.sflp | 179 | par | 0..16 | 16 | M | `Result[i] := 0x00` |
| CDROM_controller.sflp | 182 | par | 0..8 | 8 | M | `Param[i]`, `Transfer_head[i] := 0x00` |
| CDROM_controller.sflp | 185 | par | 0..4 | 4 | A | 5 register assigns (ResultTD, SetSectorPlay, SetSector, SetSectorEnd, ResultTN) |
| CDROM_controller.sflp | 674 | par | 0..8 | 8 | M | `Result[i] := Transfer_head[i]` |
| CDROM_controller.sflp | 681 | par | 0..8 | 8 | M | `Result[i] := 0` |
| DMA_CDR.sflp | 73 | any | 0..4 | 4 | M | `dma_count<1:0> == i : dma_data[i] := dma_read_data` |
| DigitalSignalProcessor.sflp | 57 | par | 0..24 | 24 | I | `ch[i].sw_spuenv_off()` |
| DigitalSignalProcessor.sflp | 61 | par | 0..24 | 24 | I | `ch[i].CtrlIRQ = CtrlIRQ` |
| DigitalSignalProcessor.sflp | 94 | any | 0..24 | 24 | I | `doing<4:0> == i : vA = ch[i].vA`; `doing == 24: vA = rvb.A` |
| DigitalSignalProcessor.sflp | 101 | par | 0..24 | 24 | I | `ch[i].vDin` |
| DigitalSignalProcessor.sflp | 111 | join | 0..24 | 24 | I | reads `ch[i].voice_out_L` |
| DigitalSignalProcessor.sflp | 114 | join | 0..24 | 24 | I | reads `ch[i].voice_out_R` |
| DigitalSignalProcessor.sflp | 118 | par | 0..24 | 24 | I | `ch[i].sw_intpl_off()` |
| DigitalSignalProcessor.sflp | 123 | join | 0..24 | 24 | I | reads `ch[i].disp_env` |
| DigitalSignalProcessor.sflp | 126 | join | 0..24 | 24 | I | `rvb_on<i>` bit selects |
| DigitalSignalProcessor.sflp | 154 | join | 0..24 | 24 | I | reads `ch[i]` |
| DigitalSignalProcessor.sflp | 158 | par | 0..24 | 24 | I | `if (ch[i].halt_out) halt(0b100 \|\| i)` |
| DigitalSignalProcessor.sflp | 184 | par | 0..16 | 16 | I | `if (io_Din<i>) ch[i].key_on()` |
| DigitalSignalProcessor.sflp | 189 | par | 16..24 | 8 | I | `if (io_Din<(i-16)<3:0>>) ch[i].key_on()` |
| DigitalSignalProcessor.sflp | 194 | par | 0..16 | 16 | I | `ch[i].key_off()` (same select form) |
| DigitalSignalProcessor.sflp | 199 | par | 16..24 | 8 | I | `ch[i].key_off()` |
| DigitalSignalProcessor.sflp | 221 | any | 0..24 | 24 | I+S | `io_A` selector → `ch[i].io_set(...)`, `ch_io_set(i)`, else `halt(0x23)` |
| DigitalSignalProcessor.sflp | 242 | any | 0..24 | 24 | I | `io_Dout = ch[i].io_get(io_A<3:0>).io_Dout`; else `halt(0x24)` |
| DigitalSignalProcessor.sflp | 251 | par | 0..24 | 24 | I | `ch[i].run()` |
| DigitalSignalProcessor.sflp | 266 | any | 0..24 | 24 | I | `doing<4:0> == i : ch[i].read_ack()`; `doing == 24: rvb.ack()` |
| GeometryTransformationEngine.sflp | 151 | par | 0..32 | 32 | M | `d[i] := 0`; `c[i] := 0` |
| GeometryTransformationEngine.sflp | 520 | alt | 0..32 | 32 | S | priority encoder: `val<31-i> : bitp = 0b0 \|\| i`; else `bitp = 32` |
| PAD.sflp | 38 | par | 0..32 | 32 | M | `data_buf[i] := 0x00` |
| PAD_controller.sflp | 57 | par | 0..256 | 256 | M | `data_buf[i] := 0x00` |
| PAD_controller.sflp | 298 | join | 4..132 | 128 | M/read | `checksum = data_buf[i] @ checksum` |
| PlayStation_core.sflp | 240 | par | 0..4 | 4 | I | `timer[i].index = i` |
| PlayStation_core.sflp | 489 | par | 0..4 | 4 | I | `timer[i].run33()` |
| PlayStation_core.sflp | 508 | par | 0..4 | 4 | I | `timer[i].run33()` |
| R3000A.sflp | 140 | par | 0..32 | 32 | A | `gpr[i] := 0`; `cpr0[i] := 0` |
| gte_DIVIDE.sflp | 50 | alt | 0..16 | 16 | S | `s_CLZ<15-i> : CLZ_ret = i`; commented-out else |
| demo/demo_core.sflp | 203 | par | 0..4 | 4 | M | `zs[i] := i` |

Declarations found for the indexed names:

- `CDROM_controller.sflp:66` `mem Result[16]<8> = {0}`; `:117` `mem Transfer_head[8]<8>`.
- `DMA_CDR.sflp:61` `mem dma_data[4]<8>`; `:14` `input dma_read_data<8>`.
- `DigitalSignalProcessor.sflp:32` `sel ch<5>` (a 5-bit selector, not an
  array); `:27–29` scalar instances `ch_00 … ch_17`; `:31`
  `instrself ch_io_set(ch)`; `:36` `instrin sw_intpl_off, sw_reverb_off,
  sw_spuenv_off`; `:47` `instrself halt(h_code)`; `:48` `sel h_code<8>`.
- `GeometryTransformationEngine.sflp` `d`, `c`: declarations not re-checked
  line by line in this pass (the body uses them as `d[i]`, `c[i]`).
- `PAD.sflp:25` `mem data_buf[32]<8> = {0}`; `PAD_controller.sflp:29`
  `mem data_buf[256]<8>`.
- `PlayStation_core.sflp:72` `Timer timer_0, timer_1, timer_2, timer_3`
  (no array); `:50` `instrself map_ram, …`.
- `R3000A.sflp:36` `mem gpr[32]<32> = {0}`; `:37` `mem cpr0[32]<32> = {0}`.
- `gte_DIVIDE.sflp:46` `sel s_CLZ<16>, CLZ_ret<4>`.
- `demo/demo_core.sflp:57` `mem zs[4]<2> = {0}`.

## Classification

Counts are by keyword, not by file.

1. **Implemented type, scalar or memory indexing (13 sites).** par/any/alt
   over declared `mem` arrays or `reg`/`sel` bits:
   CDROM_controller 179, 182, 185, 674, 681; DMA_CDR 73; GTE 151, 520;
   PAD 38; PAD_controller 57; R3000A 140; gte_DIVIDE 50; demo_core 203.
   Note: PAD_controller 57 is 256 iterations, so it is the largest single
   implemented site.

2. **Implemented type, indexed name is not an array (17 sites).** par/any/alt
   whose index is applied to a name that is not declared as an array:
   - DigitalSignalProcessor: 57, 61, 94, 101, 118, 158, 184, 189, 194, 199,
     221, 242, 251, 266 (14 sites). `ch` is `sel ch<5>`; the channel
     instances are the scalars `ch_00 … ch_17`.
   - PlayStation_core: 240, 489, 508 (3 sites). `timer` is not declared at
     all; the instances are `timer_0 … timer_3`.

   These are the "instance array" constructs the compiler does not support.
   The keyword is implemented; the indexed name is not.

3. **Unsupported keyword: `join` (6 sites).**
   - DigitalSignalProcessor 111, 114, 123, 126, 154 (5 sites; indexed-instance
     reads).
   - PAD_controller 298 (1 site; `data_buf[i] @ checksum`, 128 iterations,
     start 4).
   Compiler: `sflc.py:153–155` raises `NotImplementedError('join generator')`
   for `k == 'join'`. Probe c (below) confirms the message.

Totals: 13 + 17 = 30 implemented-type par/any/alt; 6 join; 36 sites.

## Compiler citations (`tools/sflc/sflc.py`)

All line numbers checked with `rg -an` (exit 0) on the current file.

- 77: `NameError('undeclared ' + n[1])`
- 108: `NotImplementedError('instance arrays')`
- 144: `ValueError('negative generator bound')`
- 147: `ValueError('generator expansion budget exceeded (4096)')`
- 153–155: `join` → `NotImplementedError` (line 155)
- 223: `NameError('unknown instance ' + instance)`
- 225: `NameError('unknown port %s.%s')`
- 232: `NotImplementedError('nested invocation target')`
- 266: `NameError('undeclared ' + name)`
- 324: `NotImplementedError('index of non-memory')`
- 423: `ValueError('write target is not a memory')`
- Generator expansion: 141–149 `generator_envs` (bounds via `constant()`,
  `self.expansions += count` at 146, `range(start, end)` at 148); par at
  157–158; any/alt arms at 160–164.
- `sflp_parse.py`: header checks 345–362; keyword list 86; bounds note 556;
  "bounds are constants or generator arithmetic" 607.

Compiler behaviour for the 17 indexed-non-array sites: probe a shows an
indexed instance reference fails with `NameError: undeclared l` (line 77
path). Probe d shows an indexed write to a `sel` array fails at line 423.
The `ch[i]` read path would hit line 324. I did not run the full DSP or
PlayStation_core files through the compiler; these are expected paths from
the code, not observed errors for those files.

## Probes

Directory: scratchpad `q107_probe/`. Not in the repo. Run form:
`PYTHONDONTWRITEBYTECODE=1 python3 -I tools/sflc/sflc.py <file>`.

| Probe | Source | Exit | Result |
|---|---|---|---|
| a | `declare leaf interface {…}`, `leaf l_0, l_1;`, `par(i=0;i<2;i++){ l[i].a = x<i>; }` | 1 | `NameError: undeclared l` |
| b | same declare, `l_0.a = x<i>` (scalar instance) | 0 | single-circuit form accepted |
| c | `join(i=0;i<2;i++){ y = x<i>; }` | 1 | `NotImplementedError: join generator` |
| d | `sel ch<5>; par(i=0;i<2;i++){ ch[i] := x<i>; } y = ch<0>;` | 1 | `ValueError: write target is not a memory`; no output |

Earlier: a single circuit with a child instance under `--hierarchy` gave
`expected exactly one circuit`. Child-instance probes therefore use an inline
`declare`. Probe b shows scalar instances are accepted when written out by
hand; that is the form the sources would need, not a generated form.

## Other findings

- **`cache_hit_reg`**: one reference, `R3000A.sflp:195`
  (`cache_hit_reg := 0b00;`). No declaration in the 44 sources (search by
  `rg -an` over `*.sflp`, exit 0). Width and intent are not inferred here.
- **Bare block keywords** (`par{`, `any{`, `alt{`, `join{`, `kw:`): 1089
  matches across the sources by the regex in `gen_inventory.py`. These are
  not generator headers and are not counted in the 36 sites.
- **Iteration budget**: the 4096 limit is cumulative per circuit. Per-file
  iteration sums (comment-masked, literal bounds):
  - implemented par/any/alt: 752 total (CDROM 44; DMA 4; DSP 288; GTE 64;
    PAD 32; PAD_controller 256; PlayStation_core 12; R3000A 32;
    gte_DIVIDE 16; demo 4)
  - join: 248 total (DSP 120; PAD_controller 128)
  - all sites: 1000
  The per-circuit total was **not computed**: the sums are per file, and
  the mapping from files to circuits is not established here.

## Assumptions and limits

- Site counts come from the script on the scratch list; not checked against
  a full compiler run of each file.
- Body categories and the "scalar/memory" vs "instance" split are my reading
  of each body, checked by hand on the listed lines.
- Pocket/core.sflp was read from disk while uncommitted; it has no generator
  sites. Its `reg_ws` wide-register note (~line 473) is outside this inventory.
- `tools/sflc/__pycache__` exists in the working tree and is not part of this
  deliverable.
- No fix, signal width, or instance-array design is proposed here.
