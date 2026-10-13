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
| 1,600 ticks, interpolation off | 9,576 output checks, 9,600 ADSR readbacks: **1 differing sample** (voice 14, tick 1331, L only, max 120); under investigation (suspected parameter-write timing window) |
| 1,600 ticks, interpolation on | statistics only: RMS difference 636, max 17,721 (16-bit scale), from the different interpolation shape |

## Quartus (ristisana, 25.1std Lite, 5CEBA4F23C8, virtual pins)

`DigitalSignalProcessor` (shared engine + unchanged reverb) alone: **2,780 ALMs,
2,520 registers, 5 DSP blocks, 64 RAM blocks** (524,288 bits: the reverb buffer).
The upstream 24-voice DSP needed ~33,300 comb. ALUTs and 75 DSP blocks.

Quartus 25.1 frontend pitfalls hit on the way (now avoided): a RAM with two
asynchronous read ports crashes VRFX (`ConnectReadArrayPort` /
`SplitDualReadRams`); nested `N'(signed'(...))` casts in nonblocking assignments
crash `VeriTypeCast::Evaluate`.

## Open

- The single 1,600-tick difference (above).
- Full-core synthesis/fit with the shared SPU (queued on the shared host).
- Reverb buffer (64 RAM blocks) should move to SPU RAM in SDRAM as on the real PS1;
  the RAM blocks are needed elsewhere in a full Pocket build.
- Audio output to the Pocket (44.1 -> 48 kHz, I2S): Q-L2-12.
- No hardware test yet.
