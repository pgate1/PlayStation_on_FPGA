# Authoritative diagnostic inputs — Q-L2-02 unblocked for RTL/simulation

Verified 2026-10-12. This supplies option 1 requested by the diagnostic model,
and the matching project files from option 2. Quartus is still not on PATH;
fitting/bitstream production is not yet unblocked. Do not wait for Quartus to
implement and simulate the small pixel-domain module specified below.

## Pinned primary source and local cache

Repository: [open-fpga/core-template](https://github.com/open-fpga/core-template/tree/da3a021b1eaf742604d86d8dc9b33a6666263e6a).
Revision: `da3a021b1eaf742604d86d8dc9b33a6666263e6a` (the same revision as the
existing APF fetch script, not a newly guessed timing example).

The complete reference is now cached, unmodified and gitignored, under:

```text
Pocket/build/reference/core-template-da3a021b1eaf742604d86d8dc9b33a6666263e6a/
```

Below, paths are relative to that directory. Licensed reference files stay in
the cache; this packet records facts and an independently written RTL contract.

| Input | Source and interpretation |
|---|---|
| `pixel_clock_hz` | **12,287,999**, from `src/fpga/core/mf_pllbase/mf_pllbase_0002.v:34,37`; nominally 12.288 MHz in the example comments |
| `h_total` / `v_total` | **400 / 512**, from `src/fpga/core/core_top.v:519–524` |
| Active size | **320 × 240**, same localparams and `video.json` |
| Active origin | **x=10, y=10**; active x=10..329, y=10..249 |
| Nominal refresh | About **60 Hz**, calculated as 12,287,999 / (400 × 512); this is not a measured hardware frequency |
| Horizontal sync | One positive pixel-clock pulse per line, evaluated at pre-edge x=3 |
| Vertical sync | One positive pixel-clock pulse per frame, evaluated at pre-edge x=0 and y=0; HS occurs three pixel clocks later |
| Output timing | RGB/DE/HS/VS are registered on the pixel clock and correspond to the pre-edge counter values; blanking RGB is zero, `video_skip=0` |
| Pixel clock pins | Reference `core_top.v:511–517,663–670` connects PLL outclk_0 to `video_rgb_clock`, outclk_1 to `video_rgb_clock_90` |
| Phase | PLL output 0: 0 ps; output 1: 20,345 ps, from the PLL IP parameters. Preserve these supplied IP settings for integration |
| Reference clock | 74.25 MHz is the PLL reference parameter, not the pixel frequency |

Timing source: [core_top.v, video generator](https://github.com/open-fpga/core-template/blob/da3a021b1eaf742604d86d8dc9b33a6666263e6a/src/fpga/core/core_top.v#L499-L601).
Clock source: [generated PLL parameters](https://github.com/open-fpga/core-template/blob/da3a021b1eaf742604d86d8dc9b33a6666263e6a/src/fpga/core/mf_pllbase/mf_pllbase_0002.v#L31-L38).
These values were read from the actual files, not inferred from the APF SDC.

## Matching project and hashes

The cache contains `src/fpga/ap_core.qpf` and `src/fpga/ap_core.qsf`, along with
their APF shell, PLL QIP/generated RTL, and SDC inputs. QSF specifies
`TOP_LEVEL_ENTITY apf_top`, `DEVICE 5CEBA4F23C8`, and Cyclone V; it includes the
board pin assignments. Its recorded last tool version is **18.1.1 Lite Edition**.
This does not establish that a local Quartus installation exists or that a new
diagnostic project has been fitted. Preserve the reference project intact.

| File | SHA-256 of downloaded bytes |
|---|---|
| `src/fpga/core/core_top.v` | `a036e934d56cb44c980f49c33583fe71449f6fa6a2f2bd41145590cdcb2f3666` |
| `src/fpga/core/mf_pllbase/mf_pllbase_0002.v` | `07c1a739bebf75cbababa24fb4097d7a18850e29f4aa2ae38c343f1fdf126c39` |
| `src/fpga/ap_core.qpf` | `a911d8909682cd12e9d963a88f106b816f5f737f7008d7ac8f6304de138825c9` |
| `src/fpga/ap_core.qsf` | `65d1b8989e6efa2e4d9cd361d03493a26dbda601a8fa9058b151c4fb7360acaf` |
| `src/fpga/core/core_constraints.sdc` | `c0ffbe130cfcdd588a2ab32fe1a891ce2fa12ef1723a39d4ed1062b57acf90d7` |
| `video.json` | `1ce4b3d954ecd78cebd103bcafca7225a7c2e21f9a586d9cbd30579bb8b4a49c` |

Archive URL:
`https://codeload.github.com/open-fpga/core-template/tar.gz/da3a021b1eaf742604d86d8dc9b33a6666263e6a`.
Archive downloaded to `/tmp/psx-apf-template-da3a021.tgz`, observed SHA-256
`c2553fdf893d9836fd15b0189cb7e70c29e569dea9e064e6612dd256124f0421`.
Use the per-file hashes to check identity if the archive is regenerated upstream.

## Copyable Q-L2-02 assignment: pixel-domain diagnostic module

Own only `Pocket/diagnostic/diagnostic_core.sv` and
`Pocket/diagnostic/tb_diagnostic_core.sv`. Use the exact timing above. Do not edit
the live PS1 top, cached template, QSF/SDC, compiler, PLL or APF files.

Implement module `diagnostic_core` with these ports:

```text
input clk_pixel              // supplied PLL output 0; no clock generation here
input reset_n                // active-low; caller synchronizes release to clk_pixel
input button_async           // wrapper will connect cont1_key[4] (face A)
output [23:0] video_rgb
output video_de, video_hs, video_vs, video_skip
```

Design decisions for this diagnostic task (not claims about upstream behavior):

- Reset counters, video outputs and synchronizer state deterministically. After
  reset release, the first pixel edge evaluates x=0/y=0 and asserts VS; HS is
  asserted three pixel edges later. Outputs during reset are zero.
- Synchronize only the single level-sensitive button bit through two pixel-clock
  flip-flops. It is a held button indication, not an event-counting interface.
  Do not sample the entire controller word as a supposedly coherent CDC bus.
- Sample the synchronized button at the frame boundary, and use that held value
  for the whole next frame. This avoids a color change partway through a frame.
- Within active video, draw eight vertical 40-pixel bars: white, yellow, cyan,
  green, magenta, red, blue, black. For the top-left 40×40 active-pixel patch,
  use red when the sampled A button is low and green when high. Outside active
  video RGB is zero. `video_skip` stays zero.
- Preserve one-cycle HS/VS polarity/placement and active-window boundaries above.
  Do not add conventional VGA pulse widths: APF's supplied example uses these
  short pulses and separates VS/HS.

Acceptance: a bounded Icarus bench must check at least two complete frames,
204,800 pixel clocks/frame, 512 HS pulses/frame, one VS pulse/frame, 76,800 DE
pixels/frame, all active-window edges, bar boundaries, black blanking, reset
interruption and a button change between frames. Check frame-latched behavior
with a mid-frame button toggle. Use a supplied simulation clock; no vendor PLL
simulation is needed. Report the exact command and PASS/failure; no hardware
or bitstream claim follows from this simulation.

L3 owns later integration into a separate APF diagnostic wrapper/project:
reset-release synchronization, connection to `cont1_key[4]`, PLL clocks,
APF bridge/reset/boot handshake, safe unused pins, SDC review, fitting and
packaging. The reference SDC's clock-group exceptions are not automatically
validated constraints for a modified hierarchy. Quartus is required at that
later build gate, not for this two-file implementation packet.
