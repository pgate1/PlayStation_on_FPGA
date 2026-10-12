# Preparing the independent Pocket diagnostic project

This build uses the pinned APF reference plus the independently tested color-bar
core and reset-release synchronizer. It does not compile or integrate the PS1
core. No new diagnostic bitstream has been synthesized or tested on Pocket.

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

With Quartus installed on a suitable host, compile from the prepared directory:

```sh
quartus_sh --flow compile ap_core
```

That command has **not run here**. It still must establish device support,
synthesis/fitting success, resource use, generated-clock relationships, reset
recovery/removal and all relevant timing checks. Archive reports and newly built
output hashes. Packaging into Pocket's `.rbf_r` layout and physical testing are
subsequent gates; do not rename the reference bitstream and call it a build.
Use [the test card](POCKET_DIAGNOSTIC_TEST.md) only with a recorded new artifact.
See [Quartus host prerequisites](POCKET_QUARTUS_BUILD.md) for the build-host plan.
