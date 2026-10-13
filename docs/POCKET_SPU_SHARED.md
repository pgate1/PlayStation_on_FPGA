# Time-shared SPU voice engine (Q-L1-12, roadmap P07)

Goal: real PS1 sound on the Pocket. The upstream SPU builds 24 complete voice
channels (`dsp_ch` x 24), which alone needs about 29,800 ALUTs and 72 DSP blocks,
far beyond the Cyclone V 5CEBA4F23C8. The real PS1 SPU processes its voices
serially; `Pocket/spu/spu_dsp_shared.sv` does the same.

## Design

`spu_dsp_shared` has exactly the ports and CPU/memory protocol of the
sflc-generated `DigitalSignalProcessor`. `DigitalSignalProcessor_shared.sv` wraps it
under that name and `DigitalSignalProcessor.h` declares the interface, so `sflc`
links SoundProcessingUnit to it unchanged (`prepare_core_sources.py --shared-spu`).

- One voice datapath visits the 24 voices round-robin (about 47 clocks per voice
  per 44.1 kHz sample are available at 50 MHz). Two shared signed 18x18 multipliers
  and one set of ADSR rate ROMs (the upstream `RateTable*_rom.v`).
- Per-voice state in small RAMs (MLAB), every RAM with exactly one asynchronous
  read port: CPU registers (three copies: CPU readback, engine, fetch start/loop),
  voice state, fetch state, a two-word BRR prefetch ring, envelope readback.
- BRR fetch keeps the original rotating `doing` slot (voices 0..23, reverb 24) and
  hold-until-ack protocol. The two-word prefetch per voice decouples memory latency
  from the engine; each buffered word carries its block's filter/shift and the
  end-without-keep "silent" tag, applied when the word becomes current.
- Key on/off are stamped with the 176.4 kHz tick count and applied at the same
  tick boundary as in the original. Envelope effects from older ticks never
  override a later key-on.
- The unchanged sflc-generated `reverb` module is instantiated inside, as in the
  original DSP.

Algorithms follow `dsp_ch.sflp` and `ADSR.sflp`: BRR decode (shift, filters 0-4,
clip), ADSR state machine (attack/decay/sustain/release, exponential modes,
fractional accumulator), envelope x10-bit, volume, mixing (`main_add`, reverb sends,
reverb clip) and CPU register semantics including halts 0x23/0x24.

### Deliberate differences

| Item | Original | Shared engine | Effect |
|---|---|---|---|
| Interpolation | per-clock linear ramp between pre1 and pre0 | `pre1 + (pre0-pre1)*frac` once per 44.1 kHz sample, frac from the pitch counter | different interpolation shape (see stats below) |
| Parameter sampling (pitch, ADSR, volume) | used immediately | read when the engine visits the voice, up to ~2 ticks (<= 45 us) later | inaudible; not bit-exact right after a write |
| Output update | continuous | once per voice per 44.1 kHz sample | none at the 44.1 kHz output rate |
| `disp_env` (debug LEDs) | per-voice delta-sigma | driven 0 | no audio effect |

## Verification (Icarus 13, `Pocket/spu/tb_spu_shared.sv`)

The bench runs the upstream DSP (sflc-generated, 24 x dsp_ch) and the shared
engine side by side: identical SPU RAM with 2,048 random BRR blocks (random
filters/shifts, loop/end flags), separate memory models with random 2..15-cycle
latency, random per-voice parameters, key on/off and parameter changes. Parameter
writes are made once the engine has caught up (see the sampling difference above).

```sh
SC=<scratch>; R=<repo>
python3 -I tools/pocket/prepare_core_sources.py $SC/core3 --check   # provides the reference DSP
iverilog -g2012 -s tb_spu_shared -P tb_spu_shared.TICKS=1600 -o $SC/spu.vvp \
  Pocket/spu/tb_spu_shared.sv Pocket/spu/spu_dsp_shared.sv $SC/core3/PlayStation_core.sv \
  RateTable*_rom.v mul_*.v
vvp -n $SC/spu.vvp            # add -P tb_spu_shared.INTPL=1 for interpolation statistics
```

| Run | Result |
|---|---|
| 200 ticks, interpolation off | `PASS spu_shared exact`: 1,176 per-voice output checks (L and R), 1,200 ADSR readbacks, 0 differences |
| 1,600 ticks, interpolation off | 9,576 output checks, 9,600 ADSR readbacks: 1 differing sample (voice 14, tick 1331): explained below |
| 1,600 ticks, interpolation on | statistics only: RMS difference 636, max 17,721 (16-bit scale), from the different interpolation shape |

The one 1,600-tick difference: voice 14 was keyed on again at tick 1333 while the
engine was still finishing tick 1331 for it. Key-on side effects that must reach
the fetch unit at once (prefetch flush, restart) happened before the engine
computed that older sample, so the last pre-retrigger sample of that voice
differed. Known, deliberate limitation (a voice that is being restarted anyway).

## Reverb work area in SPU RAM (`--reverb-in-spu-ram`, option O1/O1b)

Upstream already contains this path; `#define USE_BUF_RAM` selected a private
32K x 16 buffer (64 RAM blocks) instead. O1 removes the define, O1b drops the reset
generate of the buffer clear (no buffer to clear).

- `Pocket/spu/tb_reverb_equiv.sv`: buffer build vs SPU-RAM build of the unchanged
  reverb, identical inputs, after the buffer build's 32,768-cycle reset clear:
  `PASS reverb_equiv` 400 passes (399 with non-zero output), 0 differences, with
  memory latency 2..15 and 2..40 cycles.
- In the shared DSP the reverb originally got 1 of 25 memory slots; at 2..40 cycle
  latency it fell behind (71 of 100 passes). The engine now serves a pending reverb
  access next (voices have a two-word prefetch): `tb_reverb_mem.sv` 99/100 passes
  done, no backlog, at 2..15 and 2..40 cycles; exact voice test still PASS.
- Upstream quirk noted: during the buffer clear after reset (~0.65 ms) the buffer
  build's reverb results are corrupted; the SPU-RAM build has no such window.

Cost: about 36 SPU-RAM accesses per 22.05 kHz pass (~0.8 M/s). On the Pocket this
competes with CPU/VRAM on the shared SDRAM unless SPU RAM moves to a PSRAM chip.

## Quartus (ristisana, 25.1std Lite, 5CEBA4F23C8, virtual pins)

`DigitalSignalProcessor` (shared engine + unchanged reverb) alone: **2,780 ALMs,
2,520 registers, 5 DSP blocks, 64 RAM blocks** (524,288 bits: the reverb buffer).
The upstream 24-voice DSP needed ~33,300 comb. ALUTs and 75 DSP blocks.

Full `PlayStation_core` with the shared SPU, reverb in its private buffer, all pins
virtual, SPU switches free (sound fully enabled): synthesis 0 errors; **fit fails at
2,151 LABs (device 1,848), 21,285 ALMs (115%), 14,490 registers, 64/66 DSP**. The
same core with the SPU tied off needed 2,022 LABs, so full sound now costs about
130 LABs (~1,300 ALMs); the remaining overflow is the general sflc overhead
(Q-L1-13), not sound.

**Milestone (2026-10-13 14:51):** with sflc after Q-L1-13 (dca809a) and source fix F8,
the full `PlayStation_core` with full sound (shared SPU, reverb in its private buffer),
virtual pins, **fits: 16,725 / 18,480 ALMs (91 %), 13,177 registers, 84 / 308 RAM
blocks, 63 / 66 DSP**. About 1,750 ALMs remain for the Pocket top.

Quartus 25.1 frontend pitfalls hit on the way (now avoided): a RAM with two
asynchronous read ports crashes VRFX (`ConnectReadArrayPort` /
`SplitDualReadRams`); nested `N'(signed'(...))` casts in nonblocking assignments
crash `VeriTypeCast::Evaluate`.

## Open

- Default for reverb placement (option exists and is verified; decide with the
  Pocket memory layout, ideally SPU RAM on PSRAM).
- Audio output to the Pocket (44.1 -> 48 kHz, I2S): Q-L2-12.
- No hardware test yet.
