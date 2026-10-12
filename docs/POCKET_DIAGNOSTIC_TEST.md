# Pocket diagnostic hardware test card

This card applies to the isolated `diagnostic_core` described in
[POCKET_DIAGNOSTIC_INPUTS.md](POCKET_DIAGNOSTIC_INPUTS.md). It checks only the
diagnostic display and button response; it says nothing about PS1 gameplay or
frame rate. No fitted diagnostic bitstream is available yet. **All hardware
observations below are NOT RUN.**

## Build and device record

| Field | Record |
|---|---|
| Bitstream SHA-256 | ______________________________ |
| Build commit | ______________________________ |
| Quartus version | ______________________________ |
| Fit/timing report filename(s) | ______________________________ |
| Pocket firmware version | ______________________________ |
| Board / display setup | ______________________________ |
| Operator / date | ______________________________ |

Do not fill these from the cached APF reference project or its historical QSF
version. Record values from the actual diagnostic build and test. Use the
project's documented development loading procedure; this card does not specify
a menu path or packaging command. The wrapper must route face-A (`cont1_key[4]`)
to the diagnostic button input before that response can be tested.

## Expected screen

After reset release, the active image is 320 by 240 pixels, inside the supplied
400 by 512 scan timing. It has eight equal-width vertical bars, from left to
right: **white, yellow, cyan, green, magenta, red, blue, black**. The black bar
is still an active-video bar. The 40 by 40 pixel patch at the top-left of the
active image overlays the first bar: it is **red while face-A is released** and
**green while face-A is pressed**. Pixels outside the active image are black.

The button passes through a two-flop synchronizer and is sampled at the frame
boundary. The patch must keep one color for a whole frame; a mid-frame button
change must not split or tear the patch. After a stable press, expect green from
the next frame boundary that samples the synchronized input; after release,
expect red at the corresponding boundary. `video_skip` remains low.

## Operator checks

First confirm the actual image shows the eight bars and the patch without
changing controls. Release face-A and record the patch color. Press it well
before a frame boundary and check that the patch changes from red to green as a
whole patch, with no mid-frame split. Release it and check the whole patch
returns to red at a frame boundary.

Assert the diagnostic module's active-low reset using the available documented
test setup. While reset is active, RGB, DE, HS and VS are low. After release,
the pattern starts again from the beginning of a frame and remains stable. For
the red-patch check, keep face-A released through the first frame boundary after
reset so the synchronized input is sampled low. Reload the diagnostic build
using the documented development procedure and repeat the stable-image check.
Record the procedure actually used; do not infer a firmware menu path.

## Results

Every row is **NOT RUN** until someone observes it on a physical Pocket. Leave
the evidence filename empty until a capture or report exists.

| Check | Expected observation | Status (NOT RUN / PASS / FAIL) | Evidence filename / note |
|---|---|---|---|
| Color bars | Eight equal vertical bars in the listed order; black remains active video | NOT RUN | |
| Face-A released | Top-left 40×40 active patch is red | NOT RUN | |
| Face-A pressed | Whole patch becomes green at a frame boundary; no tearing | NOT RUN | |
| Face-A released again | Whole patch returns to red at a frame boundary | NOT RUN | |
| Reset | Outputs are low during reset; pattern restarts from frame origin after release | NOT RUN | |
| Reload | After reloading the same recorded build, the diagnostic image is stable again | NOT RUN | |

A diagnostic pass establishes only the observed test-core display and input
path. It does not establish PS1 boot, gameplay compatibility, audio, memory
behavior, timing closure for a later PS1 design, or any game FPS result.
