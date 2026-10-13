# BIOS boot simulation (Q-L1-15)

Verilator simulation of the sflc-translated `PlayStation_core` (all source fixes,
time-shared SPU) booting a user-supplied PS1 BIOS. The BIOS image is read from the
user's own backup and converted inside the gitignored build directory; neither the
BIOS nor captured frames (Sony artwork) are committed.

```sh
python3 -I Pocket/sim/run_boot_sim.py build Pocket/build/bootsim
python3 -I Pocket/sim/run_boot_sim.py run Pocket/build/bootsim <SCPH1001.BIN> \
    Pocket/build/bootsim/out_long --cycles 300000000 --frames-every 30
```

Harness `Pocket/sim/tb_psx_boot.sv`: memory semantics follow the upstream Pocket top
(`git show HEAD:Pocket/core.sflp` 240-353), one SDRAM model with 6-cycle latency,
separate SPU RAM, 60 Hz vblank, run33 from a 33.8688/50 MHz accumulator, BIOS mode
(`sw_cdrom_ctrl=0b11`, no disc), the GPU's `view_*` display writes captured to a
320x240 image. ASSUMPTION: `sdram_ack` is the controller's registered ready level
(drops when a request is accepted, rises when the operation completes); this is the
only reading consistent with core.sflp's use of it, but the original controller is
not available to confirm it.

## Result (2026-10-13, SCPH-1001 v2.2, MD5 924e392ed05558ffdb115408c263dccf)

300 M cycles (6.0 s of 50 MHz time, 360 frames), ~440 k cycles/s:

| Frame | PC | GPU display writes | Note |
|---|---|---|---|
| 0 | bfc00000 | 0 | reset vector |
| 60 | 80054174 | 0 | kernel copied to and running from main RAM |
| 180 | 8004a258 | 1.53 M | GPU starts drawing |
| 360 | 80059e00 | 41.8 M | **PlayStation "S" diamond logo on gray: boot animation** |

No halt codes, no memory request collisions. This is the first evidence that the
translated CPU, GTE, GPU, DMA and (time-shared) SPU run the real BIOS correctly
enough to reach the boot animation. Not established: reaching the BIOS menu/shell,
sound output, CD access, games, and hardware timing.
