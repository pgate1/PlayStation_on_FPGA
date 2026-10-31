# Pocket benchmark contract

Companion to [the roadmap](POCKET_ROADMAP.md). This is a proposed test plan, not a compatibility list or measured performance report. All current Pocket results are **unmeasured**.

## Success criteria

The target is original PS1 code at correct game speed, approximately 30 completed/presented frames per second in selected lighter scenes, with audible music and effects. Use NTSC editions initially and record the exact disc revision. PAL runs have separate timing targets.

Qualification has two stages. **Video gate (M4):** apply frame-rate, game-speed, rendering and video/memory reliability criteria below; silent output is permitted, and audio results are marked `deferred`, not passed. Keep guest SPU register/DMA behavior needed for game progression. Record resource headroom and a simulated representative audio memory load. **Combined gate (M6):** apply every criterion with required sound enabled and remeasure FPS.

Proposed acceptance for an NTSC scene whose reference sustains about 30 fps:

- At least 28.5 newly completed/presented game frames/s averaged over a fixed 120-second gameplay segment, with median frame interval near 33.3 ms and 95th percentile no worse than 50 ms.
- Game progress over that segment agrees with the same input replay on the reference within 2%; exceptions must be explained by known game nondeterminism. Do not alter guest speed to hit an FPS counter.
- No audio FIFO underruns, SPU deadline misses, scanout underruns, lost commands or halts after the warm-up period.
- Audible expected music and effects, correct pitch/channel balance, no growing A/V drift over ten minutes. Report measured latency and source features, including SPU, CDDA, XA and reverb.
- No missing scene geometry, UI, textures or required blend/copy effects. Full image equality is appropriate for subsystem fixtures; game captures may require timing alignment and documented rasterization tolerances.

These thresholds are proposed engineering gates. Capture the reference first. If a scene genuinely runs below 30 fps on PS1, record that behavior and choose another light scene for the 30 fps gate; do not “fix” the original game's timing. A 60 fps game running at half speed fails even if the display shows 30 fps.

## Games and scenes

| ID | Game / proposed edition | Fixed scene | Why it is useful | Gate |
|---|---|---|---|---|
| B0 | BIOS menu, local polygon demo, PS-X EXE fixtures | Cold boot, controller navigation, fixed demo duration | Reproducibility and quick isolation without CD streaming | Smoke tests; no claim of game performance |
| B1 | Doom, NTSC-U `SLUS-00077`; pin actual image hash | Hangar start: stationary view, fixed turning route, then firing/doors/enemies for 120 s | Reverse-engineered PS1 code, repeatable gameplay, SPU audio, texture/CLUT and CPU workloads | Primary 30 fps candidate, subject to reference capture |
| B2 | WipEout (1995), NTSC edition; pin serial/revision | Altima VII time trial: fixed craft/settings; 120 s from race-start cue | Early 3D workload, GTE, textured polygons, streaming and CD music | Primary 30 fps candidate; racing is not assumed cheap until profiled |
| B3 | Crash Bandicoot (1996), NTSC edition matching reference symbols | N. Sanity Beach: fixed opening route, crates/spin/jump actions | C reconstruction and game-engine symbols help identify CPU/GTE/CD/SPU behavior | Secondary compatibility and scaling target |
| B4 | Castlevania: Symphony of the Night, NTSC-U `SLUS-00067` | Fixed Castle Entrance corridor route, then one fixed effect-heavy scene; log starting inventory/save | Matching decompilation, sprites, palette changes, blending, uploads and audio | 2D stress/regression; do not call 30 fps half-speed playback a pass |
| B5 | XI and/or Ridge Racer from this project's README | Fixed puzzle sequence or race segment, pinned region/settings | Existing partial-compatibility control avoids measuring only newly booted games | Preserve/improve measured baseline; reference native timing governs |
| B6 | GUNPEY (Japan) from user backup `roms/sony/psx/Gunpey (Japan).zip`; `.bin` SHA-256 `c04448b34e251adfe90a3689c80388b8e5d97849bf3c74c9453441e3ce5816f5`, `.cue` SHA-256 `52126e755b4b00344e8f6f41d8a3ccd565613276a2081afc5a819821fbb18fe3`; edition label from filename only, disc not yet verified | Fixed puzzle sequence from a recorded input replay; scene not yet captured | Lightest candidate for the first end-to-end video + audio target; workload not yet measured | First target: boot, correct speed and video; then audio (step two). Do not claim a pass until the reference is captured |

None of B1–B4 is listed as working in this snapshot's README. Their first gate is boot/gameplay compatibility. B5 provides a control while those gaps are repaired. A “simple” game is defined by its captured workload, not its visual style.

Doom is especially useful because its two rates are explicit: the reverse-engineered header distinguishes a 15 Hz main timebase and a 30 Hz original rendering cap. Measure each separately. [PsyDoom `doomdef.h`](https://github.com/BodbDearg/PsyDoom/blob/master/game/Doom/doomdef.h)

WipEout's rewrite author documents the original assumption of 30 fps physics steps. Use that information to understand timing, while measuring the original PS1 executable. [Author's technical account](https://phoboslab.org/log/2023/08/rewriting-wipeout)

## Reference projects and their roles

### User-reported MIRLO64 hardware results

Reported directly by the user on 2026-10-11 after trying games on Pocket:

| Game as reported | Observation |
|---|---|
| Tony Hawk | Runs; dips only a little below 30 fps in the first level |
| Mario Kart | Runs fairly steadily; numeric frame rate not specified |
| “wave rider” | Runs; exact title not confirmed, possibly Wave Race 64 |
| Star Fox | Runs; frame rate dips in polygon-heavy scenes |
| Mario 64 | Runs; numeric frame rate not specified |

These are firsthand user observations, not measurements made during this analysis. Exact game editions, Tony Hawk installment, region, MIRLO64 bitstream/revision, audio state, capture duration and FPS measurement method are unspecified. Do not fill those fields from assumptions. In particular, do not identify the installed bitstream with the inspected source revision or infer audio performance from “runs.”

The reports provide hardware evidence beyond MIRLO64's README and make its implementation a stronger reference for Pocket resource allocation and performance work. Star Fox's heavy-scene dips motivate measuring geometry, rasterization and memory stalls separately; they do not identify which subsystem caused the dips. N64 results do not predict a PS1 title's FPS. If these runs are formalized later, distinguish MIRLO64's framebuffer-origin counter from completed game frames using its `docs/fps.md` caveats.

### PS1 reference projects

| Reference | Role | Limits |
|---|---|---|
| [PSXDOOM-RE](https://github.com/Erick194/PSXDOOM-RE) | PS1-specific reverse engineering, code paths and optional instrumented diagnostic builds | Keep modified builds separate from retail acceptance; do not require rebuilding its legacy SDK just to start benchmarking |
| [PsyDoom](https://github.com/BodbDearg/PsyDoom) | Understanding Doom's renderer, audio and deterministic demo behavior | Native PC renderer/FPS and modern defaults are not PS1 hardware performance |
| [WipEout rewrite](https://github.com/phoboslab/wipeout-rewrite) | Game structure, fixed-point/timing discussion and workload interpretation | A reimplementation, not a matching PS1 binary or cycle oracle |
| [Crash `c1`](https://github.com/wurlyfox/c1) | PS1 graphics/CD interfaces, audio structures and game routines | C reconstruction/port; do not assume every symbol address or behavior matches the chosen disc |
| [SotN decomp](https://github.com/Xeeynamo/sotn-decomp) | Matching decompilation and symbols for supported revisions, including the US edition | Match the exact revision and overlay before applying addresses |
| [DuckStation](https://github.com/stenzek/duckstation) | Original-binary reference captures and subsystem implementation to investigate | Pin version/settings; no PGXP, upscaling, CPU overclock, widescreen patches or frame-rate hacks. Emulator timing is not a universal hardware oracle |
| [PSn00bSDK](https://github.com/Lameguy64/PSn00bSDK) | Small PS-X EXE fixtures for GPU, DMA, timing and SPU | Fixtures isolate problems; they do not replace game testing |

For disputed timing or hardware quirks, cross-check a second independent emulator or actual PS1. Record reference disagreements rather than adjusting the core to one unexplained output. Pin reference commits in benchmark manifests; current upstream branches can change.

The FPGA runs original machine code. Decompilations supply symbols and explanations; no game-specific offload, rebuilt desktop game, or altered executable counts toward the general PS1-core target.

## Capture procedure

1. Record bitstream/source hashes, BIOS checksum, game serial/region/revision and disc/track hashes, Pocket firmware, toolchain/seed and settings. Keep game/BIOS assets external to the repository.
2. Capture the chosen route in the reference emulator at normal speed, original resolution and without enhancement patches. Record video, stereo audio, input timing and game progress. Establish which features the scene uses and its native cadence.
3. Capture GP0/GP1 commands, SPU register/DMA events, CD commands and selected CPU/GTE markers where tooling permits. PC symbol addresses must come from the exact binary or matching symbol map; do not invent them.
4. Replay those subsystem traces in small simulation benches before full-system testing. Distinguish untimed functional streams from timestamped traces used to check timing. Preserve event order and DMA dependencies.
5. Cold boot the Pocket build. Use recorded controller samples indexed by guest VBlank or a documented replay protocol; record the corresponding wall-clock times. A shared input trace does not by itself prove synchronization.
6. Warm up for 10 seconds after the scene cue, then measure the fixed 120-second route. Record load/boot times separately. Do three cold-boot runs and retain each result.
7. Run a ten-minute sound/streaming/thermal stability segment. Capture a reproducible glitch timestamp plus the recent device events on failure.
8. Compare sound-enabled performance against the same build muted. Muting at the serializer must not disable SPU computation; separately label any build that compiles the SPU out.

Physical captures through a Dock are convenient when available. Captured output may contain repeated display refreshes; combine video analysis with core counters. Internal instrumentation should have a small, measured resource cost.

## What to measure

| Measurement | Meaning |
|---|---|
| Output refresh Hz | Pocket scanout cadence; often around 60 Hz, not game FPS |
| Display-origin / flip events | Software presentation requests; can overcount or miss in-place updates |
| GPU completion time | Rendering work finished; command completion alone does not define a whole game frame |
| Presented game frames | Completed content displayed with a defensible frame-boundary rule; corroborate using moving scenes/video |
| Game update count / progress | Whether guest time matches wall time; Doom's main timebase differs from rendering |
| CPU useful cycles / retired instructions | Execution throughput; do not treat `cpu.run` pulses as retired instructions |
| Stall breakdown | Exclusive primary cause plus separately labeled overlapping conditions |
| Memory traffic | Requests, burst lengths, bytes, worst/p95 latency, refresh stalls and fairness |
| Texture/CLUT statistics | Hit/miss ratios and external reads per rendered pixel |
| Audio health | Sample counts, FIFO min/max, underruns, overflows, deadlines, pitch and A/V drift |
| Video health | FIFO minima, missed line deadlines and mode/origin changes |
| Fit and timing | ALMs, DSPs, RAM blocks/bits, all relevant timing corners and unconstrained-path audit |

Neither frame hashes nor flip counters alone reliably measure game FPS: static frames can be valid, in-place rendering may never flip, and repeated origin writes may not display new work. Define a per-scene frame boundary using command completion, presentation state and capture evidence. Always report the measurement method.

## Required focused fixtures

- Cache fills at each word offset, tag replacement, cache clear and texture-cache commands.
- Multi-master memory with byte masks, backpressure, refresh, reset and row/burst crossings.
- GP0 FIFO pressure and reset; DMA linked lists; CPU progress while GPU draws.
- Raster → VRAM readback → texture reuse; CLUT changes, copies, masks, blending and lines.
- SPU ADPCM filters/flags, pitch extremes, envelope transitions, saturation, looping, all 24 voices, RAM DMA/IRQ and worst-case refill collisions.
- 44.1-to-48 kHz sample accounting; signed stereo I2S; full/empty/flush behavior.
- CD seeks and window boundaries, short reads, errors, data/audio interleaving and track changes.
- Timer/VBlank/IRQ tests under CPU stalls; display origin/mode changes without status-read side effects.

## Result record template

Create one record per run. Null means unmeasured, never zero.

```yaml
benchmark_id: B1
qualification_stage: video
scene: hangar_route_v1
status: unmeasured
audio_status: deferred
source_revision_or_manifest_sha256: null
bitstream_sha256: null
bios_sha256: null
disc_serial: SLUS-00077
disc_revision: null
disc_track_hashes: []
region: NTSC-U
pocket_firmware: null
quartus_version_and_seed: null
reference_emulator_revision: null
reference_settings_file: null
input_trace_sha256: null
audio_features_enabled: []
render_features_missing: []
measurement_method: null
wall_seconds: null
reference_presented_fps: null
pocket_presented_fps: null
frame_ms_median: null
frame_ms_p95: null
game_progress_error_percent: null
audio_underruns: null
spu_deadline_misses: null
video_underruns: null
av_drift_ms_after_10_minutes: null
boot_and_load_seconds: null
alms: null
ram_blocks: null
ram_bits: null
dsps: null
worst_setup_slack_ns: null
worst_hold_slack_ns: null
artifacts: []
known_failures: []
```

Report rows remain unmeasured until a real capture exists. Simulated cycles, successful synthesis, a boot logo, and the bundled historical fitter summary do not establish Pocket gameplay performance.
