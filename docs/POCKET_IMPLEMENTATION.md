# Implementation checkpoint — 2026-10-12

## Current continuation — hierarchy and native sequential probes

See [POCKET_SFLC.md](POCKET_SFLC.md) for the current boundary: hierarchy linking,
multiple-task stages, thirteen local regression groups, fifteen combinational
reference cases and five sequential reference cases pass. The p18 mismatch was
traced to data selector qualification and fixed using native p23–p26. The earlier
universal inactive-zero assumption was incorrect; see the qualified behavior
and remaining expression-simplification limits in the compiler document. `reg_ws` wide-register reset
was corrected from all-ones to numeric 1 using native evidence.

Commits `6fbe8bc` (compiler/cache milestone) and `95d42dd` (another agent's HDL
runner/evidence) and `0422745` (hierarchy/stage milestone) exist. An isolated oracle branch was pushed for Linux CI.
No Pocket bitstream, fit, timing closure or hardware FPS has been established.
The [diagnostic plan](POCKET_DIAGNOSTIC_PLAN.md) defines an earlier visible screen
and input milestone, conditional on platform/build prerequisites.

## Earlier checkpoint — superseded where stated below

### Historical first compiler/cache milestone

See [POCKET_SFLC.md](POCKET_SFLC.md) for the detailed implementation boundary,
commands, results and remaining semantic risks. `tools/sflc/sflc.py` now supports
registers, local control terminals/arguments, memories, lexical locals, switch and
single-task stages in addition to the earlier combinational subset.

- `python3 tools/sflc/tests/run_tests.py`: **nine groups PASS**, including 4,000
  sequential cycles, 65,536 numerical vectors, 242 actual-source cache checks,
  detection of both independently reverted suffix-validity fixes, and 19 real
  leaf-module elaborations.
- `tools/sflc/cosim.py`: **nine existing combinational oracle cases PASS**, 4,000
  vectors each (seed 1). Reference artifacts remain external.
- Both generated caches: **Verilator 5.052 lint PASS, no warnings**.
- New native probes p17–p19 await independent sequential reference runs.
- `.github/workflows/sflc.yml` was added; remote execution is not claimed.

No SFL source bytes or live Pocket RTL were changed by the 2026-10-12 work.
No source-to-bitstream build, synthesis, timing or FPS measurement was performed.
P02 now has experimental-compiler behavioral evidence; it is not fully qualified.
P00/P04 remain open. The working directory is a Git checkout; no commit or push
was made in this session.

## Historical implementation record — 2026-10-11

The sections below preserve earlier evidence. Statements such as "not a Git
checkout", "no simulation", "switch left for a stronger model", and unavailable
Verilator describe earlier checkpoints, not the current state. Current status is
[POCKET_START_HERE.md](POCKET_START_HERE.md).


## Saved changes

- `Pocket/rtl/psx_mem_fabric.sv`: one backend transaction at a time; one response slot per owner; separate urgent/fair round-robin pointers and bounded urgent preference; invalid-range/length rejection; zero-mask write completion; stable registered backend request; same-cycle backend acceptance/completion support; sticky unexpected-response flag.
- `Pocket/rtl/psx_mem_word_adapter.sv`: 1–8 halfwords to 1–5 aligned 32-bit commands, masks and odd-address alignment; one controller read outstanding; response buffering; tag checking; synchronous common reset. Writes complete after the controller accepts every effective word.
- `Pocket/rtl/psx_mem_frontend.sv`: connects those two modules, exposing a MIRLO-style word-controller interface. Does not instantiate a controller, PHY or CDC.
- `Pocket/rtl/psx_mem.f`: source list, paths relative to project root.
- `Cache_IR.sflp:103` and `Cache_Texture.sflp:153`: changed the second duplicated `offset==0` to `offset==1` in word-2 suffix-fill validity. Exact byte replacements preserved all other bytes, including CRLF and original comment encoding.

All files are saved in the workspace. No Git commit exists: this project folder is not a Git checkout. No MIRLO source was copied or changed.

## Compilation evidence

Icarus 13.0, executed from the project root. Each command below exited **0 with no diagnostics**:

```sh
iverilog -g2012 -Wall -s psx_mem_frontend -t null -c Pocket/rtl/psx_mem.f
iverilog -g2012 -Wall -s psx_mem_frontend -Ppsx_mem_frontend.N=1 -Ppsx_mem_frontend.URGENT_MAX=0 -Ppsx_mem_frontend.TAGW=1 -t null -c Pocket/rtl/psx_mem.f
iverilog -g2012 -Wall -s psx_mem_frontend -Ppsx_mem_frontend.N=7 -Ppsx_mem_frontend.URGENT_MAX=1 -Ppsx_mem_frontend.TAGW=5 -t null -c Pocket/rtl/psx_mem.f
```

These establish syntax/elaboration only. **No testbench was added or run; no behavioral simulation, synthesis, timing closure or Pocket measurement was performed.** The SFL fixes cannot be compiled with the currently available toolchain.

Earlier `/usr/bin/time -l` wrappers failed with `sysctl kern.clockrate: Operation not permitted`; no peak-memory figure was obtained. Plain compiler invocations above succeeded. Do not report the failed wrapper's exit status as an HDL failure or its output as reliable resource measurement.

## Controller review and assumptions

The inspected neighbor revision was `d5c714cca0c128d36295ef770cf0d891086d4889`. Its `rtl/soc/sdr_ctrl.sv:138–142` asserts `req_ready` when it schedules READ/WRITE; `dfi_wrdata_en` follows the write command. This supports the adapter's ordered write-acceptance interpretation by source inspection only. Physical visibility still depends on correct controller/PHY timing.

The controller returns reads through an `RL` pipeline, rather than directly using `dfi_rddata_valid`. Its clock/PHY alignment must be reproduced and constrained; changing frequency or RL speculatively can return the wrong data. Tie lookahead inactive initially if reusing the controller. Preserve source licenses and pin imported revisions.

## Next model: do this first

1. Read the actual RTL and `POCKET_MEMORY_CONTRACT.md`. Review ownership, packed byte ordering, odd-address five-word bursts, per-owner response stalls, non-power-of-two client counts and simultaneous accept/complete edges.
2. Under the active session's testing authorization, add a behavioral scoreboard and execute the contract's cases. Compilation is not proof of these behaviors.
3. Recover P00's SFL/compiler/platform dependencies. Keep P04 open until controller, legacy client adapters, CDC and internal DMA ownership are integrated.
4. Keep existing CPU/GPU stalls. The frontend is deliberately not wired into `Pocket/core_top.v`, and removing stalls now remains unsafe.
5. Validate the cache patches with all suffix offsets, replacement and reset once generated RTL can be built.

## Known limitations

- This conservative implementation serializes backend bursts and individual read words. It is a correctness foundation, not a demonstrated throughput optimization.
- A stuck backend stalls further requests. Wrong-tag reads set a sticky fault and are ignored. There is no timeout/recovery mechanism; safe recovery requires quiescing/resetting the entire transaction path.
- Constant read tag zero is valid only while this adapter exclusively owns its controller response stream. Do not merge a second direct controller requester behind it.
- All blocks share one clock and common reset. Independent producer/controller reset, stale responses across reset, loader CDC and APF traffic buffering are unresolved integration work.
- `N >= 1`, `URGENT_MAX >= 0`, `TAGW >= 1` are required parameter constraints. No synthesis resource budget has been measured.
- No error/timeout input exists at the word-controller interface; `rsp_error` reports invalid requests, not physical SDRAM failures. Sticky protocol flags need system-level handling.
- No rendered-frame or FPS improvement has been measured. P02 and P04 are **not complete**.

## Behavioral validation of the frontend — 2026-10-11 (Icarus 13.0)

Bench: `Pocket/tb/tb_psx_mem.sv` (self-checking, no waveform dump). Run from the project root:

```sh
iverilog -g2012 -s tb_psx_mem [-Ptb_psx_mem.N=.. -Ptb_psx_mem.URGENT_MAX=.. -Ptb_psx_mem.TAGW=..] -o tb.vvp -c Pocket/rtl/psx_mem.f Pocket/tb/tb_psx_mem.sv
vvp tb.vvp +seed=<n> +cycles=<per-phase cycles, default 6000>
```

Covered: N clients with random requests (len 0–15, even/odd addresses, random/full/zero/out-of-length byte masks, reads, writes) checked against a halfword reference model; low region and the exact top of the 64 MiB aperture; invalid length/address; zero-effective-mask writes; backend ready 20–100 %, read latency 0–7 incl. same-cycle result; response stalls (including one client consuming at 2 % while others progress); consume and accept on the same edge; urgent saturation with the starvation bound checked per client; random resets under load (reference resynced, no stale response accepted); controller request held stable under backpressure; no zero-enable write commands; sticky fault on an unexpected read result, cleared by reset.

Results: **PASS** for N/URGENT_MAX/TAGW = 1/0/1, 2/1/2, 6/4/3, 7/1/5, 3/8/4, each with seeds 1–4 at +cycles=3000; default config also passed at 6000 cycles. Max observed wait equalled the proposed bound N·(URGENT_MAX+1)−1 in every config (the bound is tight, not violated). Five hand-made mutants (adapter odd-shift removed, zero-mask word not skipped, address limit off by one, urgent counter not reset, fair pointer not advanced) were each caught.

**No RTL bug was found.** Not covered: fabric `b_rsp_valid` without a request (not reachable via the frontend), controller-specific timing (refresh, turnaround), reads with latency overlapping a following command (adapter issues one read at a time), CDC, synthesis, timing, bandwidth. Fairness bound is in selections, not cycles. Wall time was not measured (`/usr/bin/time -l` is blocked here).

## Non-blocked Pocket items — 2026-10-11 (Icarus 13.0)

Status: items 1–3 and 5 done; item 4 fetch script done, distribution licence decision open; `switch` work left for a stronger model.

### 1. `ram_320x240x15_dp` replacement

- RTL: `Pocket/rtl/ram_320x240x15_dp.sv`. Bench: `Pocket/tb/tb_ram_320x240x15_dp.sv`.
- Run from the project root:
  `iverilog -g2012 -s tb_ram_320x240x15_dp -o tb.vvp Pocket/rtl/ram_320x240x15_dp.sv Pocket/tb/tb_ram_320x240x15_dp.sv && vvp tb.vvp +seed=3`
- Result: `PASS tb_ram_320x240x15_dp: 150351 reads checked, 200000 ops, 0 errors`
- Assumptions: port names are guessed because the sfl-generated `.h` is not in the repository. Read is registered (one cycle). Same-address read/write returns the old value. The 17-bit address is used as-is (depth 76800).

### 2. Async SRAM controller (`sram_ctrl`)

- RTL: `Pocket/rtl/sram_ctrl.sv`. Bench: `Pocket/tb/tb_sram_ctrl.sv`.
- Run: `iverilog -g2012 -s tb_sram_ctrl -o tb.vvp Pocket/rtl/sram_ctrl.sv Pocket/tb/tb_sram_ctrl.sv && vvp tb.vvp +seed=3 +ops=4000`
- Result: `PASS tb_sram_ctrl: 4002 commands, 0 errors`
- Timing (one clock per phase): read = address and OEn at T, sample Dout at T+2, ack at T+3. Write = address, Din and DEn at T, WEn low for one clock, DEn released and ack at T+3. UBn and LBn are held low.
- Assumptions, not verified against the real device:
  - Interface matches the generated `sram.read/write/ack/dout` calls only by guess.
  - Clock period and SRAM access/pulse timings are not checked against the datasheet or the actual SRAM clock.
  - SRAM size: resolved. `core_top.v` has `sram_a[16:0]` and `sram_dq[15:0]`, which is 128K × 16 = 256 KiB, matching the docs. The earlier "1M × 16" label was wrong; the bench already uses `WORDS = 1 << 17`.
  - `rd_req` wins if both requests are high. Requests are ignored while busy.

### 3. `vjtag_uart` recovery

- Copied to `hdl/USB-JTAG/DE0-CV/`: `vjtag_uart.h`, `vjtag_uart.v`, `VirtualJTAG.v`, `LICENSE_USB-Blaster_UART`.
- Source: `pgate1/USB-Blaster_UART` (master), MIT, Copyright 2019 pgate1. Licence verified via the GitHub API.
- Syntax check: iverilog with a stub `sld_virtual_jtag`. Only warnings were the missing timescale and a floating `ir_out` port, both present upstream. The real `sld_virtual_jtag` is a Quartus-only primitive and was **not** simulated.
- **Fixed:** `Pocket/core.sflp` line 13 now includes `../hdl/USB-JTAG/DE0-CV/vjtag_uart.h` (was `../../../…`, which resolved outside the repo).

### 4. APF shell — fetch-at-build, licence decision open

- `open-fpga/core-template` `src/fpga/apf/*` and `src/fpga/core/core_bridge_cmd.v` carry Analogue's Software License Agreement, not MIT. It grants no redistribution right. **Nothing is committed.**
- `tools/apf/fetch_apf.sh` downloads 13 files from core-template at pinned revision `da3a021b1eaf742604d86d8dc9b33a6666263e6a`. Each file is checked against a pinned SHA-256, and the files go to `Pocket/build/apf/`, which is gitignored. Re-running uses the cache.
- Public precedent: the Neo Geo core `Mazamars312/Analogue_Pocket_Neogeo` (HEAD `988163bc…`) vendors the same APF files. That shows practice, not licence compatibility.
- Deferred: no release build is planned. A built core zip or bitstream containing APF-derived code is a distribution question for later.

### Open

- `switch`, instrout/instrself, stages/states and `mem` in `Pocket/core.sflp` remain for a stronger model.
- Route 2 (Overtone licence) is undecided; the P00 build is blocked on it.
- No commits or pushes have been made.

### 5. P04 controller — imported unchanged, not adapted

- Copied from MIRLO64 HEAD `23d8dea926ece5877262abb414497bc6ddf06e7d` to `hdl/SDRAM/MIRLO64/` (earlier notes cited `1ab630b…`; the copied revision is the one above):
  - `sdr_ctrl.sv` SHA-256 `cc1d5b18639d52fd6e35cd18380ebd6e2341b2ebbb89d1a861a36d45b51de46b` (Apache-2.0, `LICENSE-APACHE-2.0`).
  - `sdr_phy.sv` SHA-256 `84a2a16106dd570cd74b0b2b8d051f98f236d6157df81cab6971327408457ee9` (LiteX-derived, BSD 2-Clause, `LICENSE-LITEX-BSD-2-CLAUSE`).
- `LICENSE-LITEX-BSD-2-CLAUSE` is LiteX's upstream `LICENSE` file verbatim (SHA-256 `8371c1e1e72db0c21eba5acfec4f4f8597dc8555bd282b2a35ccbbde992675c5`), replacing an earlier hand-written copy.
- Check: `iverilog -g2012 sdr_ctrl.sv` elaborates (iverilog warns about constant selects in `always_*`). `sdr_phy.sv` fails elaboration on `ALTDDIO_OUT`, which is Quartus-only, as expected.
- Not adapted. The donor is 32-bit word, 62.832 MHz, and tuned to board timing. The PS1 wrapper needs 16-bit addressing and 128-bit returns, and the clock ratio must be retimed. None of that can be verified without hardware.
- Details are in `hdl/SDRAM/MIRLO64/README.md`.
