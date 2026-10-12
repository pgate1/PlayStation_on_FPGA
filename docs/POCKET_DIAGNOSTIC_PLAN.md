# Pocket diagnostic screen before the PS1 game milestone

Updated 2026-10-12 from a read-only inspection of this workspace. This plan defines a small visible hardware milestone that does not depend on the PS1 compiler, BIOS, main SDRAM controller, or game execution.

## Current feasibility

The diagnostic core is a sensible first hardware milestone, but it is **not currently a start-to-finish local build**. The workspace has the Pocket APF shell files cached under `Pocket/build/apf/` (13 files, fetched by `tools/apf/fetch_apf.sh` at a pinned revision), an existing `Pocket/core_top.v`, and Icarus/VVP plus Verilator on PATH. `quartus_sh`, `quartus_map`, `sflp`, and `sfl2vl` are not on PATH. There is no Pocket `.qpf` or `.qsf`; the only checked-in fit summary is from an older successful fit, not a build recipe or evidence for current sources. No board pins, working diagnostic pixel timing, PLL settings, or currently usable Quartus installation were established by this inspection.

The cached APF shell is a useful starting input, but its presence does not supply the missing project assignments or generated PLL. The active PS1 top references `main_pll_0002`, `sdram128_burstn_ctrl_100`, and synchronizer modules, and its video output assignments are incomplete/commented. It also depends on a missing SFL include for the SRAM controller. Those are game-core dependencies; a diagnostic design should bypass them entirely.

The previously discussed **1–3 focused workdays** is a planning range only if a working Quartus installation with Cyclone V support, the exact Pocket project/pin constraints, and a known-good video timing reference are available at the start. With the current local state, those prerequisites are unresolved, so the range is not a reliable completion estimate. Do not start by inventing QSF pin assignments, PLL values, or display timing.

## Shortest diagnostic-to-hardware path

Keep this work in a new diagnostic project area, such as `Pocket/diagnostic/`, and package its output separately from the PS1 core. Reuse the pinned APF shell only under its applicable terms; do not copy licensed APF files into tracked source or distribute a resulting package until the existing distribution question is resolved.

| Gate | Work | Acceptance evidence |
|---|---|---|
| D0: unblock exact platform inputs | Obtain a Quartus environment that can compile for Cyclone V `5CEBA4F23C8`, plus the matching APF QPF/QSF and board constraints from an authoritative Pocket/core-template project. Identify an APF-supported minimal video test core or an existing Pocket timing example. Record source revisions, licenses, and hash of each input. | `quartus_sh --version` records the installed version; the selected project/constraint source and revision are recorded. Review confirms every pin assignment and clock constraint is copied from an authoritative matching project. Missing or incompatible files remain explicit blockers. |
| D1: isolate an APF diagnostic core | Create a small SystemVerilog implementation of the APF `core_top` interface, or use the authoritative test-core interface if its revision differs. It generates a fixed color-bar/checker pattern and changes one visible region when `cont1_key` changes. Tie unused outputs to safe values established from the matching APF example and Pocket port contract. It must not instantiate the PS1 core, SDRAM/SRAM controllers, BIOS loader, or missing PLL IP. | Icarus compile/elaboration of the diagnostic top and a small testbench passes. Testbench checks reset, stable pattern/timing signals, and at least one controller-button response. No PS1 source or game resource appears in the diagnostic synthesis hierarchy. |
| D2: fit and timing | Build using the D0 QPF/QSF and the pinned APF shell. Resolve only actual compiler/fitter errors. Inspect the inferred hierarchy, unused outputs, pin conflicts, clock report, and setup/hold results. Do not suppress or false-path a clock simply to obtain a green report. | `quartus_sh --flow compile <diagnostic-project>` completes. Archive fit, pin, clock, and TimeQuest reports. Verify the intended top/device, no unconstrained diagnostic clocks, no pin conflicts, and no critical timing failures. Record resource use as measured output, not a forecast. |
| D3: package and show on hardware | Package only the diagnostic RBF and required APF metadata in a separate test core. Load it on the physical Pocket using the documented development flow. Check that the pattern is stable and visible, button input changes the expected region, and boot/reload returns reliably. Capture a short video plus core revision and board/firmware details. | A reviewer can reproduce the load from the archived package; visual output and button response are directly observed. Record any scaler-mode or Dock dependence. This proves only APF display/input bring-up, not PS1 execution or performance. |

The output timing source for D1 must come from the D0 reference. `Pocket/core_top.v` comments describe 74.25 MHz input clocks, and the cached APF SDC declares 13.468 ns clocks for `clk_74a`, `clk_74b`, and `bridge_spiclk`; these values alone do not establish the required pixel cadence or PLL configuration. Do not substitute a guessed divider or assume an arbitrary sync period will be accepted by the scaler.

## Keep the PS1 milestone separate

The diagnostic screen can demonstrate project synthesis, APF packaging, board loading, scaler output, and controller input. It does not validate the SFL-to-Verilog hierarchy, game clocks, SDRAM, SRAM, loader, VRAM, audio, timing under load, or game compatibility.

The PS1 path remains a distinct sequence: finish the experimental SFL compiler control/sequential work; link all modules and generated interfaces; recover or replace the missing PLL, SDRAM controller, and SRAM controller; reconcile the Pocket shell and memory/CDC contracts; restore actual video output and produce a complete project; then fit, qualify, and test original BIOS/game binaries on Pocket. The old `Pocket/ap_core.fit.summary` reports 17,060/18,480 ALMs, 307/308 RAM blocks, and 58/66 DSPs, but it is dated 2025-12-03 and does not qualify the present workspace. No game boot, new fit, current timing closure, or Pocket frame-rate evidence follows from the diagnostic milestone.

## Small cross-provider task packets

These packets have bounded files and can be assigned independently. L1 means inventory, evidence formatting, or mechanical checks under a schema. L2 means a small implementation with focused simulation. Neither packet tier authorizes guesses about physical pinout or timing.

### L1: project and artifact preflight

**Inputs:** `Pocket/build/apf/`, `tools/apf/fetch_apf.sh`, `Pocket/core_top.v`, `Pocket/ap_core.fit.summary`, and this plan.

**Owned output:** add `Pocket/diagnostic/inputs.json` and `Pocket/diagnostic/check_inputs.py` only. Inventory cached APF files against the fetch script's pinned SHA-256 values, list absent project/PLL/controller inputs, record tool availability and the source of every proposed constraint, and mark license/distribution decisions. The checker should be read-only and should fail when a required hash or status field is missing. Do not invoke the network, fetch assets, or edit APF/core RTL.

**Acceptance:** `python3 Pocket/diagnostic/check_inputs.py` emits deterministic JSON/text status; a deliberately changed expected hash or omitted required field is rejected. Report current absence of Quartus and QPF/QSF explicitly rather than treating an old fit report as a build.

### L2: diagnostic display/input core

**Prerequisite:** D0 supplies an authoritative APF test-core interface and pixel timing contract. Do not begin implementation against guessed values.

**Inputs:** matching APF example top/interface, matching Pocket constraints, and `Pocket/core_top.v` only as a port-name reference.

**Owned output:** add `Pocket/diagnostic/diagnostic_core.sv` and `Pocket/diagnostic/tb_diagnostic_core.sv`; do not modify `Pocket/core_top.v`, `Pocket/core.sflp`, the PS1 RTL, APF shell, or QSF/SDC. Implement a fixed test pattern and one controller-driven visual change, with deterministic reset and safe unused outputs supported by the platform contract.

**Acceptance:** `iverilog -g2012 -s tb_diagnostic_core -o /tmp/diagnostic.vvp Pocket/diagnostic/diagnostic_core.sv Pocket/diagnostic/tb_diagnostic_core.sv && vvp /tmp/diagnostic.vvp` passes the pattern, reset, and button checks. The hardware acceptance is D2/D3; a passing simulation is not called visible Pocket progress.

### L1: build/evidence capture after project recovery

**Prerequisite:** D0 and a Quartus installation are available.

**Owned output:** add `Pocket/diagnostic/README.md` and a small report-collection script under `Pocket/diagnostic/`. The script may invoke only the named diagnostic Quartus project and gather fit/TimeQuest reports; it must not edit constraints, suppress warnings, or launch a full PS1 compile.

**Acceptance:** `quartus_sh --flow compile <diagnostic-project>` exits successfully and the collector records tool version, device, project revision, pin/clock report paths, timing status, resource summary, and package hash. An absent Quartus command or missing report is a hard failure with a clear message. Physical visibility and input response remain D3 observations.

## Present blockers and next action

The shortest useful next action is to secure D0 inputs: a working Quartus installation with Cyclone V support, the exact matching APF project/constraints, and a known-good Pocket video test-core timing reference. Once these are available, the diagnostic shell can proceed without waiting for the PS1 compiler or game-memory architecture. Until then, local work can inventory and review files, but cannot honestly produce a fitted bitstream or guarantee a visible image on hardware.
