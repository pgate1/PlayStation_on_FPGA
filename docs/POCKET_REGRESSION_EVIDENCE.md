# Pocket HDL regression evidence

Run with `tools/pocket/run_regressions.sh [LOG_DIR]`. The script builds each bench in a temporary directory, keeps per-test logs, and exits nonzero on any compile or simulation failure. It dumps no waveforms.

These are isolated behavioral benches. They are not full-system simulation, synthesis, timing, or hardware results.

## Tools

| Tool | Version | Path |
|---|---|---|
| Icarus Verilog (`iverilog`) | 13.0 (stable), v13_0 | `/opt/homebrew/bin/iverilog` |
| Icarus runtime (`vvp`) | 13.0 (stable), v13_0 | `/opt/homebrew/bin/vvp` |

## Results

| Date | Test | Exact configuration | Result | Log |
|---|---|---|---|---|
| 2026-10-12 | psx_mem default | `iverilog -g2012 -s tb_psx_mem -c Pocket/rtl/psx_mem.f Pocket/tb/tb_psx_mem.sv`; `vvp -n +seed=3 +cycles=6000` | PASS | per-run temp dir |
| 2026-10-12 | psx_mem min (`N=1 URGENT_MAX=0 TAGW=1`) | same, with `-Ptb_psx_mem.N=1 -Ptb_psx_mem.URGENT_MAX=0 -Ptb_psx_mem.TAGW=1`; `+seed=3 +cycles=6000` | PASS | per-run temp dir |
| 2026-10-12 | psx_mem wide (`N=7 URGENT_MAX=1 TAGW=5`) | same, with `-Ptb_psx_mem.N=7 -Ptb_psx_mem.URGENT_MAX=1 -Ptb_psx_mem.TAGW=5`; `+seed=3 +cycles=6000` | PASS | per-run temp dir |
| 2026-10-12 | ram_320x240x15_dp | `iverilog -g2012 -s tb_ram_320x240x15_dp Pocket/rtl/ram_320x240x15_dp.sv Pocket/tb/tb_ram_320x240x15_dp.sv`; `vvp -n +seed=3` | PASS: 150351 reads checked, 200000 ops, 0 errors | per-run temp dir |
| 2026-10-12 | sram_ctrl | `iverilog -g2012 -s tb_sram_ctrl Pocket/rtl/sram_ctrl.sv Pocket/tb/tb_sram_ctrl.sv`; `vvp -n +seed=3 +ops=4000` | PASS: 4002 commands, 0 errors | per-run temp dir |

Overall: all five passed in the run recorded above (`RESULT: all regressions passed`, exit 0).

## Negative checks

| Date | Check | Result |
|---|---|---|
| 2026-10-12 | Empty PATH (`env -i /bin/bash tools/pocket/run_regressions.sh`) | `ERROR: required tool not found in PATH: iverilog`, exit 2 |
| 2026-10-12 | Copy of the repo with the SRAM bench's PASS string changed to `XPASS` | `sram_ctrl` reported `FAIL (no PASS line)`, `RESULT: 1 regression(s) failed`, exit 1. Other four still passed. The copy was in the scratch directory, not the repository. |

## Not measured

Runtime, memory use, coverage, and resource or timing numbers are not recorded. The benches are bounded by the seeds and cycle/op counts above; they do not show that these counts are sufficient.

## Assumptions

- The per-run logs are in temporary directories; they are not archived in the repository. Pass `LOG_DIR` to keep them.
- Port names and timing of `sram_ctrl` and `ram_320x240x15_dp` were assumed, not checked against the real SRAM datasheet or the original RAM interface (see `docs/POCKET_IMPLEMENTATION.md`).
