# Pocket audio output (P05): SPU mix to Pocket I2S

Status: RTL and simulation evidence only. Nothing has been synthesized with
Quartus, integrated in `Pocket/core_top.v`/`Pocket/core.sflp`, or heard on a
Pocket. Claim: `docs/claims/Q-L2-12.md`.

Files (all new, `Pocket/audio/`):

| File | Content |
|---|---|
| `pocket_audio_out.sv` | RTL: `pocket_audio_out` (top), `pocket_audio_sat21`, `pocket_audio_resampler`, `pocket_audio_afifo`, `pocket_audio_i2s_tx` |
| `tb_resampler.sv` | 44.1→48 kHz accuracy and sample accounting |
| `tb_clip.sv` | 21→16-bit clipping, exhaustive and through the resampler |
| `tb_i2s_cdc.sv` | End to end: two clocks, FIFO, I2S, receiver model decoding MCLK/LRCK/DAC |
| `run_audio_tests.sh` | Runs lint, all benches and the mutation checks |

## Design

```
clk_50 (core)                                     clk_74a (APF, 74.25 MHz)
in_l/in_r 21b ─ sat21 ─ resampler ─ FIFO write ═╪═ FIFO read ─ prime/run ─ i2s_tx ─ audio_mclk
sample strobe ──┘        147/160      (16 x 32b, gray pointers)    hold/udf        ├ audio_lrck
(ext / run33 / acc)                    ovf: drop newest                               └ audio_dac
```

### Sample strobe (`SAMPLE_SRC`)

| Value | Source | Rate |
|---|---|---|
| 0 | `sample_en`: one `clk_core` pulse per 44.1 kHz sample | Caller-defined |
| 1 | Counts `run33` pulses and fires every 768th | 33.8688 MHz / 768 = 44 100 Hz (`DDS_50to33868800` is exact: 50 MHz × 10584/15625) |
| 2 | Phase accumulator: `STB_INC`/`STB_MOD` of `clk_core` | 50 MHz × 441/500000 = 44 100 Hz exactly |

Deriving `sample_en` from the DSP (best option, needs an SPU port that is
**not** added here): the DSP advances on `run33` when `dcount == 192`
(176.4 kHz tick). Every fourth tick is a 44.1 kHz sample. In
`Pocket/spu/spu_dsp_shared.sv`, this is the cycle where `run33 && dcount == 192`
and the tick counter's two least significant bits wrap (`tick_cnt[1:0] == 3`
before the increment). A pulse taken there is phase-aligned with the engine.
The time-shared engine updates voices one by one after the tick. If the mix
must be fully settled, delay the pulse until the engine has finished that
visit. Mode 1 has the same average rate, follows emulation pauses (`run33`
is gated in `Pocket/core.sflp:206-207`), but its phase is arbitrary. A voice
can therefore be one 44.1 kHz sample late in the captured sum. That is
inaudible, but it is not bit-exact. Mode 2 ignores emulation pauses.

### Saturation

`pocket_audio_sat21` clips to [-32768, 32767] and never wraps. The upstream
`DigitalSignalProcessor.sflp` reverb-input clip only checks the
`<20:15>` patterns `111110`/`000001`. This block clips every 21-bit value.

### Resampler (exact 147/160)

All positions are integers in units of 1/160 input period. After reset, the
model treats `x[-1] = 0` as position 0. Input `x[k]` is at `160(k+1)` and
output `n` is at `147n`. When `x[k]` arrives, every output with
`160k ≤ 147n < 160(k+1)` is produced, where `ph = 147n − 160k`:

`y = round_half_up(prev + (curr − prev)·ph/160)`

The calculation is done exactly in offset binary (`u = s + 32768`):

- `N = 160·u_prev + (u_curr − u_prev)·ph + 80`, where 0 ≤ N < 2²⁴.
- `y_u = ⌊⌊N/32⌋/5⌋`.
- `⌊m/5⌋ = (m·419431) >> 21`, checked exhaustively for 0 ≤ m < 2¹⁹ in Python.

`ph` is a 9-bit integer. Every 147 inputs produce exactly 160 outputs, so the
phase cannot drift. One input produces one or two outputs. A two-channel
time-shared finite-state machine (FSM) needs at most 16 `clk_core` cycles per
input; the actual budget is about 1134. If a strobe arrives while the FSM is
busy, the sample is dropped and counted in `dbg_ovf_count`.

Quality limits of linear interpolation, measured in `tb_resampler`: compared
with the ideal continuous sine at the 48 kHz instants, SNR is **54.6 dB at
1 kHz** and **15.0 dB at 10 kHz**. The 10 kHz error is mostly the
interpolator's sinc² droop (about −1.5 dB) plus imaging. Treble is therefore
audibly dulled and some aliasing images remain. This is acceptable for the
first audible milestone. A polyphase FIR is the upgrade path, and the
fixed 147/160 phase bookkeeping can stay. The SPU's own Gaussian
interpolation is separate from this block.

### FIFO and clock crossing

`pocket_audio_afifo` is a dual-clock FIFO with 16 entries of
`{L16, R16}`. It uses binary/gray pointers, two-flop synchronizers in each
direction, and one more register on the read side before the level is used.
The RAM has one write port and one *registered* read port. There are no
asynchronous read ports.

- **Overflow:** a write while full is dropped (newest sample lost) and
  `dbg_ovf_count` increments. The counter saturates at 16 bits and is in the
  core domain.
- **Prime/run:** after reset, the output is silence (0) until 8 frames
  (`PREFILL`) are queued. In run mode, one frame is popped per 48 kHz frame.
- **Underflow:** if the FIFO is empty at fetch, the last frame is repeated,
  `dbg_udf_count` increments (audio domain, saturating), and the block returns
  to prime mode. Every repeated frame after the first start counts as one
  underflow, including frames repeated while re-priming.
- **Reset:** `rst_core` resets the write side synchronously. The audio-side
  reset is asserted asynchronously and released synchronously after three
  `clk_74a` flops. MCLK, LRCK and the bit counter are free-running and use
  power-up values only, so reset never truncates an I2S frame. During reset,
  the data is 0.
- There is no rate adaptation. A real core/audio rate mismatch therefore
  appears as periodic, counted drops or repeats, never as pitch change.

### I2S transmitter (template format)

The template does not contain a serializer that carries data.
`Pocket/build/reference/core-template-da3a021…/src/fpga/core/core_top.v:607-650`
(same as the current `Pocket/core_top.v:719-762`) only generates silence. It
does fix the clocking:

- MCLK uses a fractional accumulator on `clk_74a`:
  `+245760`, wrap at `742500`, toggle. This gives exactly 12.288 MHz on
  average.
- SCLK is `aud_mclk_divider[1]`, which is MCLK/4 = 3.072 MHz.
- Data is written on `negedge` SCLK.
- LRCK toggles every 32 SCLK, which gives 48 kHz.
- The template comment says each channel has 16 active bits followed by 16
  dummy bits.

The data shifter reproduces the APF example logic kept in MIT-licensed
`sound_i2s.sv` by Adam Gastineau
(MIRLO64 donor `target/pocket/sound_i2s.sv:77-95, 133-153`; read-only, not
copied verbatim):

- At slot 31, the shifter is reloaded with `{R, L}` when LRCK rises.
- On slots 0-15 it shifts.
- The resulting format is: LRCK low = left, LRCK high = right; 16-bit two's
  complement, MSB first, MSB one SCLK after the LRCK edge (I2S one-bit delay);
  slots 17-31 are dummy.

This implementation is different in one respect: there are **no derived
clocks**. The template's ripple clocks (`audgen_mclk`, `aud_mclk_divider[1]`)
are listed as unconstrained in `docs/POCKET_DIAGNOSTIC_BUILD.md`. Here,
everything runs on `clk_74a` with enables. `audio_mclk` is a register output,
as in the template. DAC/LRCK change one `clk_74a` cycle (13.5 ns) after the
MCLK rising edge that is the SCLK falling edge. The bench checks that DAC
stays stable from the first through the third MCLK rising edge of every bit,
where the second is the receiver's SCLK rising edge. The template's MCLK
already has ±1 `clk_74a` cycle of jitter, because each half period is 3 or 4
cycles. This design keeps that property unchanged. MIRLO64 uses an audio PLL
(`mf_audio_pll`, 12.288/3.072 MHz) instead. That is an option if hardware
shows the accumulator MCLK is insufficient.

### Interface

```
pocket_audio_out #(SAMPLE_SRC, STB_INC=441, STB_MOD=500000, FIFO_AW=4, PREFILL=8, RATIO_NUM=147)
  core:  clk_core, rst_core (sync, active high), in_l[20:0], in_r[20:0] (signed),
         sample_en, run33
  audio: clk_74a -> audio_mclk, audio_lrck, audio_dac
  debug: dbg_in_count[31:0], dbg_out_count[31:0], dbg_ovf_count[15:0]  (clk_core)
         dbg_udf_count[15:0], dbg_level_min[4:0], dbg_running          (clk_74a)
```

`RATIO_NUM` is a parameter only so the bench can test a wrong ratio. It must
stay 147. The test-only defines `PA_MUT_WRAP` and `PA_MUT_SWAP` must never be
set in a build.

## Verification

Tools: Icarus Verilog 13.0 and Verilator 5.052 on macOS. Run the commands from
the repository root. Logs were written to a scratch directory outside the
repository. The runner command is:

```
AUDIO_TB_OUT=<dir> Pocket/audio/run_audio_tests.sh [test ...]   # no args = all
```

For each test, the runner calls these commands. Here `$A` = `Pocket/audio`.

```
verilator --lint-only -Wall --top-module pocket_audio_out -GSAMPLE_SRC={0,1,2} $A/pocket_audio_out.sv
iverilog -g2012 [defines] -o X.vvp -s <tb> $A/pocket_audio_out.sv $A/<tb>.sv && vvp -n X.vvp [plusargs]
```

The final run is one invocation per test, run in parallel. Every
`script_exit` was 0:

| Test | Defines / plusargs | Exit | Result line |
|---|---|---|---|
| lint | Verilator `-Wall`, SAMPLE_SRC 0/1/2 | 0 | clean (no warnings) |
| resampler | — | 0 | `PASS tb_resampler: mode=full inputs=44100 outputs=48000 per-input-accounting-errors=0 value-checks=96000 (tol 0.5 LSB) busy_drops=0` (max \|hw−double\| = 0.5000 LSB, ties rounded up) |
| mut_ratio | `-DRATIO=148` | 1 (expected) | `FAIL tb_resampler: inputs=44100 outputs=47676 accounting_err=44034 tol_err=91461 …` |
| clip | — | 0 | `PASS tb_clip: exhaustive=2097152 named=12 resampler_outputs=958 (inputs=880) errors=0` |
| mut_wrap | `-DPA_MUT_WRAP` | 1 (expected) | `FAIL tb_clip: exhaustive=2097152 resampler_outputs=958 errors=2032526` |
| i2s_nominal | `+ms=40` | 0 | `PASS tb_i2s_cdc: SRC=2 ppm=0 jit=0ps expect=exact frames_L=1918 frames_R=1919 matched=1910/1910 holds=0 skips=0 udf=0 ovf=0 stab_err=0 lrck_len_err=0` |
| i2s_jitter | `+jit=1500 +phase=777 +seed=7` | 0 | same counts, `jit=1500ps` |
| i2s_ppm_pos | `+ppm=200 +jit=500 +phase=9000 +seed=3` | 0 | same counts, udf=0 ovf=0 |
| i2s_ppm_neg | `+ppm=-200 +jit=500 +phase=1500 +seed=4` | 0 | same counts, udf=0 ovf=0 |
| i2s_run33 | `-DSRC=1`, `+phase=5000 +jit=300 +seed=5` | 0 | `SRC=1 … matched=1910/1910 … udf=0 ovf=0` |
| i2s_underflow | `+ppm=-20000 +expect=udf +seed=6` | 0 | `… matched=1875/1875 holds=35 skips=0 udf=35 ovf=0 …` |
| i2s_overflow | `+ppm=20000 +expect=ovf +seed=8` | 0 | `… matched=1910/1910 holds=0 skips=31 udf=0 ovf=31 …` |
| mut_swap_tb | `-DTB_SWAP_INPUTS` (L/R crossed at the DUT inputs) | 1 (expected) | `FAIL tb_i2s_cdc: errors=3821 (L err=1909 R err=1911 …)` |
| mut_swap_rtl | `-DPA_MUT_SWAP` (serializer loads `{L,R}`) | 1 (expected) | `FAIL tb_i2s_cdc: errors=3821 (L err=1909 R err=1911 …)` |

All `tb_i2s_cdc` runs had a 37 ms measurement window and measured
`MCLK 12288000.0 Hz` and `frames 48000.00 Hz`. Every LRCK half period was
exactly 128 MCLK rising edges. In exact mode, every sample produced was
decoded in order, apart from the 8–9 samples still queued at the end of the
simulation. `dbg_level_min` was 8. The underflow and overflow cases show
deterministic handling: decoded holds equal `dbg_udf_count`, and decoded gaps
equal `dbg_ovf_count`.

What `tb_i2s_cdc` checks:

- Clock edges are scheduled from absolute time, so rounding does not drift.
  `+jit` adds bounded, non-accumulating phase jitter to every edge of both
  clocks.
- The receiver model sees only MCLK/LRCK/DAC. It derives SCLK = MCLK/4 from
  the LRCK edge and samples slots 1-16.
- The expected values come from the bench's own integer model of the
  interpolator, using the values the bench drove. A DUT signal is used only
  for the timing of the sample strobe. That is why channel swaps are caught.

Long-run accounting used Verilator with the same `tb_resampler.sv` in
count-only mode, because Icarus is too slow for this:

```
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style --top-module tb_resampler \
  -Mdir <dir> Pocket/audio/pocket_audio_out.sv Pocket/audio/tb_resampler.sv
<dir>/Vtb_resampler +nin=26460000 +nocheck +gap=17      # 10 minutes of 44.1 kHz input
```

Result: exit 0, `PASS tb_resampler: mode=count-only inputs=26460000
outputs=28800000 per-input-accounting-errors=0`. This is exactly 10 min ×
48 000, and the exact count was also checked after every input. The same
binary run without plusargs repeats the full value check.

## Resource expectations (estimate, not synthesized)

- About 400–450 flip-flops in total:
  - resampler ≈ 140;
  - FIFO pointers and synchronizers ≈ 35;
  - transmitter ≈ 70;
  - debug counters ≈ 100, removable;
  - strobe generator ≤ 32.
- Roughly 300–500 ALMs.
- FIFO storage is 16 × 32 bits, which needs one M10K or MLAB cells.
- Multipliers: one 17×9 signed and one 19×19 constant multiply, so about 1–2
  DSP blocks. Quartus may map them to LUTs instead.
- No PLL.

None of this has been measured. P05's resource gate requires a fit report.

## Integration notes (not done; `core.sflp`/`core_top.v` were not edited)

1. **`Pocket/core.sflp`:**
   - Remove `psx.sw_spu_off();` (line 219). `PlayStation_core.sflp:254-263`
     zeroes `voice_L/R` while it is set. Keep or drop `sw_reverb_off` and
     `sw_spuenv_off` (lines 218 and 220) according to P07.
   - Restore the SPU memory handlers commented at lines 317–353 (roadmap: 317–350), as P07
     requires. Without them the SPU has no sample data.
   - Export the mix: declare `output sound_L<21>, sound_R<21>;` and assign
     `sound_L = psx.voice_L; sound_R = psx.voice_R;`. `PlayStation_core`
     already outputs `voice_L/voice_R<21>` (line 80).
   - For `SAMPLE_SRC=1`, also export `instrout run33_o;` in the same branch as
     `instruct dds.run psx.run33();` (lines 206-207). For `SAMPLE_SRC=0`, use
     the DSP-aligned 44.1 kHz pulse instead. That needs a new SPU or
     `PlayStation_core` output.
2. **`Pocket/core_top.v`:**
   - Delete the silence generator (lines 719–762) and the three `assign`s
     to `audio_mclk/audio_dac/audio_lrck`.
   - Add `Pocket/audio/pocket_audio_out.sv` to the Quartus project.
   - Instantiate the block:

   ```verilog
   pocket_audio_out #(.SAMPLE_SRC(1)) u_audio (
       .clk_core(clk_50), .rst_core(core_rst_50),
       .in_l(sound_L), .in_r(sound_R), .sample_en(1'b0), .run33(run33_o),
       .clk_74a(clk_74a),
       .audio_mclk(audio_mclk), .audio_lrck(audio_lrck), .audio_dac(audio_dac),
       .dbg_in_count(), .dbg_out_count(), .dbg_ovf_count(),
       .dbg_udf_count(), .dbg_level_min(), .dbg_running());
   ```

   - `core_rst_50` must be synchronous to `clk_50`, for example
     `synch_3` of `~reset_n` into `clk_50`. Today `CU` receives
     `p_reset(~reset_n)` directly from the `clk_74a` domain. `audio_adc`
     stays unused.
3. **SDC:** `clk_50` comes from `main_pll` on `clk_74a`, so TimeQuest treats
   the two clocks as related. Constrain the crossing explicitly. For example:
   - `set_max_delay -from *u_audio|u_fifo|wgray[*] -to *u_audio|u_fifo|wgray_r1[*] 13.4`;
   - the mirror constraint `rgray → rgray_w1` with 20;
   - `set_false_path` or `set_max_delay` from the FIFO memory to `rdata`. The
     pointer protocol keeps an entry stable for at least two read clocks
     before it is read;
   - `set_false_path -to *u_audio|rst_aud_s[*]`, for the asynchronously
     asserted reset.

   Otherwise, put the two clocks in asynchronous clock groups. The audio output
   pins remain unconstrained, as they are in the template.
4. **Debug:** route `dbg_*` to the P01 counter page. The roadmap already names
   "audio FIFO minimum level/underruns". To read an audio-domain counter from
   the core domain, use a snapshot handshake, not a direct read.

## Open risks / assumptions

- **Format assumption:** LRCK low = left and the one-bit delay come from the
  APF example logic preserved in `sound_i2s.sv` and from standard I2S. The
  official Analogue documentation page was not fetched for this packet.
  Pocket hardware must confirm channel order and pitch with a recording
  (roadmap gate H).
- **Rate match:** zero drift requires the emulated `run33` rate and the 48 kHz
  output to share one time base. Both are derived from `clk_74a`, but the
  `main_pll` configuration for the PS1 build is not in the repository (P00).
  If `clk_50` is not exactly 50 MHz, a ppm error becomes periodic, counted
  repeats or drops. For example, ±200 ppm gives about 10 per second. When the
  emulator runs slower than real time, or pauses (`run33` gated), the output
  underflows by design.
- **SPU cadence:** the current upstream DSP updates channels at 176.4 kHz.
  Taking every fourth value decimates without filtering, but real PS1 output
  is also 44.1 kHz. With the time-shared engine, the sum is sampled while
  voices may be mid-update, as described above.
- **Clocking:** the accumulator MCLK keeps the template's ±13.5 ns edge
  jitter. Whether the Pocket's receiver tolerates it is untested here; the
  template and the MIRLO64 lineage imply it does. The PLL alternative is
  documented above.
- **Not checked:** Quartus synthesis/fit, timing, resource use, and Quartus
  RAM inference for the FIFO, which may be MLAB or registers. The RTL avoids
  dual asynchronous read ports and nested signed size casts in nonblocking
  assignments.
