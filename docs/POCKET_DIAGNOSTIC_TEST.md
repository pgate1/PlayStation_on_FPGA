# Pocket diagnostic hardware test card

This card applies to the isolated `diagnostic_core` described in
[POCKET_DIAGNOSTIC_INPUTS.md](POCKET_DIAGNOSTIC_INPUTS.md). It checks only the
diagnostic display and button response; it says nothing about PS1 gameplay or
frame rate. The first physical Pocket check confirmed the diagnostic screen,
its color-bar order and right-button response. Further checks remain pending.

## Build and device record

| Field | Record |
|---|---|
| Bitstream SHA-256 (`.rbf_r`) | `5ed526b0411cf8e35874a2589ecbaf7e105b4629d3b621bdf896a57de26e0fc3` |
| Build commit | `cd190b5` (source hashes are recorded in the ignored build manifest) |
| Quartus version | Quartus Prime Lite 25.1std.0 Build 1129 |
| Fit/timing report filename(s) | `Pocket/build/diagnostic-quartus-25.1/output_files/ap_core.fit.rpt`; `ap_core.sta.rpt` |
| Pocket firmware version | ______________________________ |
| Board / display setup | ______________________________ |
| Operator / date | User report, 2026-10-13 |

The fit completed with 0 errors, but TimeQuest reported unconstrained clocks
and I/O paths; this image is for a diagnostic trial, not timing signoff. Do not
fill the remaining fields from the cached APF reference project or its
historical QSF version. Record values from the actual physical test. Use the
project's documented development loading procedure; this card does not specify
a menu path. The wrapper routes `cont1_key[4]` to the diagnostic button input.
The user identified the control used in the hardware check as the right button.

## Expected screen

After reset release, the active image is 320 by 240 pixels, inside the supplied
400 by 512 scan timing. It has eight equal-width vertical bars, from left to
right: **white, yellow, cyan, green, magenta, red, blue, black**. The black bar
is still an active-video bar. The 40 by 40 pixel patch at the top-left of the
active image overlays the first bar: it is **red while the right button is
released** and **green while it is held**. Pixels outside the active image are
black.

The button passes through a two-flop synchronizer and is sampled at the frame
boundary. The patch must keep one color for a whole frame; a mid-frame button
change must not split or tear the patch. After a stable press, expect green from
the next frame boundary that samples the synchronized input; after release,
expect red at the corresponding boundary. The user's report confirms green
only while the button is held. `video_skip` remains low.

## Operator checks

The user confirmed the diagnostic screen appears with bars from left to right:
white, yellow, cyan, green, magenta, red, blue, black. The patch changes from
red to green while the right button is held, returning to red when released.
Frame-boundary behavior and tearing have not yet been separately checked.

Assert the diagnostic module's active-low reset using the available documented
test setup. While reset is active, RGB, DE, HS and VS are low. After release,
the pattern starts again from the beginning of a frame and remains stable. For
the red-patch check, keep the right button released through the first frame
boundary after reset so the synchronized input is sampled low. Reload the diagnostic build
using the documented development procedure and repeat the stable-image check.
Record the procedure actually used; do not infer a firmware menu path.

## Results

Mark only observations reported from a physical Pocket; leave the evidence
filename empty when the evidence is a user report rather than a capture.

| Check | Expected observation | Status (NOT RUN / PASS / FAIL) | Evidence filename / note |
|---|---|---|---|
| Color bars | Eight equal vertical bars in the listed order; black remains active video | PASS | User report: white, yellow, cyan, green, magenta, red, blue, black |
| Right button released | Top-left 40×40 active patch is red | PASS | User report: red when released |
| Right button held | Whole patch becomes green; no tearing | PASS | User report: green only while held; tearing not checked |
| Right button released again | Whole patch returns to red | PASS | User report: returns to red on release |
| Reset | Outputs are low during reset; pattern restarts from frame origin after release | NOT RUN | |
| Reload | After reloading the same recorded build, the diagnostic image is stable again | NOT RUN | |

A diagnostic pass establishes only the observed test-core display and input
path. It does not establish PS1 boot, gameplay compatibility, audio, memory
behavior, timing closure for a later PS1 design, or any game FPS result.
