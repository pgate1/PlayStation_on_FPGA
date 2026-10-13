# Preparing the independent Pocket diagnostic project

This build uses the pinned APF reference plus the independently tested color-bar
core and reset-release synchronizer. It does not compile or integrate the PS1
core. A first diagnostic image was synthesized on 2026-10-13; physical Pocket
testing remains pending.

```sh
# Offline verification, if the cache is already present:
python3 tools/apf/fetch_diagnostic_reference.py
# Or fetch the pinned official source archive:
python3 tools/apf/fetch_diagnostic_reference.py --download

# Run the standalone pixel/reset simulations:
python3 tools/pocket/run_diagnostic.py

# Pick a new output directory; existing builds are never overwritten:
PYTHONDONTWRITEBYTECODE=1 python3 tools/pocket/prepare_diagnostic.py \
  --output Pocket/build/diagnostic-new

# Audit the prepared inputs before moving them to a build host:
python3 tools/pocket/check_diagnostic_project.py Pocket/build/diagnostic-new
```

The tool copies only the verified reference's FPGA project tree, excludes old
`output_files`, `db` and `incremental_db`, and replaces the example video section
with `Pocket/diagnostic/apf_video.vh`. It adds the two diagnostic SV sources to the
QSF, preserving the pinned pin assignments, PLL files and SDC. The original
reference cache and live `Pocket/core.sflp` are not edited. New projects contain
no inherited SOF/RBF; the reference's existing bitstream is not our diagnostic.

`diagnostic_build.json` records the reference revision, input hashes, every
prepared project-file hash and explicit not-run/pending hardware checks. Build
outputs and metadata stay under gitignored `Pocket/build/`. Do not commit fetched
vendor files or hand-edit the prepared wrapper as the authoritative source.

## Integration decisions

- Host bridge and boot/setup status retain the pinned `clk_74a` implementation.
- Video clocks retain PLL outputs 0 and 1 and their supplied phase settings.
- Either host reset assertion or raw PLL lock loss asynchronously asserts pixel
  reset. Deassertion requires two rising pixel edges; the video core starts on
  a subsequent edge. A stopped pixel clock cannot release reset.
- Only face-A, `cont1_key[4]`, enters the diagnostic's two-flop button synchronizer;
  its held value is sampled at a frame boundary. No controller bus CDC is implied.
- The diagnostic has no savestates or target-initiated transfers. Formerly
  undriven reference controls are explicitly tied inactive; eight target request/
  parameter declarations become wires driven by constant assignments.
- Reference peripheral tie-offs and I2S silence generation are retained. The
  inherited asynchronous clock-group exceptions require actual TimeQuest review.

## Evidence and open gates

Pixel bench: three complete frames, 618600 checked samples, exact sync/DE counts,
bar boundaries, button behavior and reset interruption; Linux and local PASS.
Reset bench: five two-edge releases and four asynchronous assertions, including
PLL loss, held resets, source ordering and a stopped clock; local PASS. Both
independent modules pass Verilator lint without warnings.
The runner now requires each bench's independent PASS marker and successful
process exit. Temporary reset benches with a wrong marker or a fatal error after
the correct marker were both rejected. Linux CI has passed the earlier video-only
runner; the extended two-bench workflow has not yet run on Linux.

The preparation was exercised locally at `Pocket/build/diagnostic-reviewed`:
manifest file hashes matched, no upstream RBF/SOF was copied, and attempting to
reuse an existing destination failed without altering it. The prepared `core_top`
and real `core_bridge_cmd`/`common.v` structurally elaborated in Verilator 5.052
using **interface-only PLL and datatable stubs**, with `-Wno-fatal`. This is not
warning-free lint or a behavioral test of the PLL/bridge/RAM. Warnings include
unused synchronizer edge pins, datatable width truncations, incomplete cases,
combinational nonblocking assignments and initialization/clocked-writer handling
in the reference. An Icarus 13 attempt rejects reference forward declarations;
the reference sources were not rewritten to hide that failure.

## First Quartus result (2026-10-13)

The isolated prepared project was copied to `ristisana` and compiled in a
separate directory, leaving `Pocket/build/diagnostic-reviewed` as the pristine
input. Host: 64-bit Windows, Ryzen 7 5800X (8 cores), 256 GB free disk.
Quartus Prime Lite 25.1std.0 Build 1129 with Cyclone V support compiled a project
whose QSF recorded Quartus 18.1.1. This newer-tool run is useful first-build
evidence, but does not establish compatibility with the original 18.1.1 release.

Command, run from the copied directory:

```powershell
E:\altera\quartus\bin64\quartus_sh.exe --flow compile ap_core
```

Quartus completed in 3 minutes 12 seconds with **0 errors and 184 warnings**.
Fitter status is Successful for Cyclone V `5CEBA4F23C8`: 415/18,480 ALMs, 734
registers, 2/308 RAM blocks, 1/4 PLLs, and 224/224 pins assigned. The generated
`.sof` is for JTAG debug; the raw RBF is the packaging input.

The worst constrained setup slack was +5.425 ns and worst constrained hold
slack +0.170 ns across the reported corners, with zero TNS on those checks.
TimeQuest also reports **2 unconstrained internal clocks** (`aud_mclk_divider[1]`
and `audgen_mclk`), 4 unconstrained input ports, 22 unconstrained output ports,
29 unconstrained input paths and 25 unconstrained output paths. The inherited
SDC names two unused PLL outputs, and the reports flag non-dedicated routing for
`bridge_spiclk`, incomplete I/O assignments and 117 pins without output-enable
assignments. Therefore the successful flow and positive slack on constrained
paths are **not full timing signoff**. Keep this limitation visible when trying
the diagnostic image.

Captured files are under ignored
`Pocket/build/diagnostic-quartus-25.1/output_files/`. The RBF is 788,200 bytes,
SHA-256 `73a554ddb1196c21b83720b3d40c646bed2d3251f2d7b890b90d98d3fe787a3b`.
`tools/pocket/convert_rbf_r.py` performs Analogue's per-byte bit reversal, and
`tools/pocket/prepare_diagnostic_package.py` creates a standalone diagnostic SD
package with no game or BIOS slot. The verified package is
`Pocket/build/diagnostic-package-25.1/pgate1.PocketDiag_0.1.0_20261013.zip`;
its RBF_R is 788,200 bytes with SHA-256
`5ed526b0411cf8e35874a2589ecbaf7e105b4629d3b621bdf896a57de26e0fc3`. The ZIP
contains the required seven parseable JSON files and the new bitstream. The
converter was checked against known vectors, inverse conversion and exact
length; the package content and hashes were independently verified.

The ZIP is a candidate for a first physical display/button/reset test, not a
PS1 image. Do not treat it as timing-certified. Record the actual Pocket model,
OS, installation procedure and results in the [test card](POCKET_DIAGNOSTIC_TEST.md).
The bitstream and Quartus reports stay in the local ignored build directory;
they are not tracked or pushed.
See [Quartus host prerequisites](POCKET_QUARTUS_BUILD.md) for the build-host plan.
