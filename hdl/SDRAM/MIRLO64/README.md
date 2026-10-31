# SDRAM controller and PHY (imported from MIRLO64)

Files copied unchanged from MIRLO64 (`/Users/dst/Documents/koodi/MIRLO64`):

| File | Source | SHA-256 |
|------|--------|---------|
| `sdr_ctrl.sv` | `rtl/soc/sdr_ctrl.sv` | `cc1d5b18639d52fd6e35cd18380ebd6e2341b2ebbb89d1a861a36d45b51de46b` |
| `sdr_phy.sv`  | `rtl/soc/sdr_phy.sv`  | `84a2a16106dd570cd74b0b2b8d051f98f236d6157df81cab6971327408457ee9` |

Pinned to MIRLO64 HEAD `23d8dea926ece5877262abb414497bc6ddf06e7d`.

Licences:
- `sdr_ctrl.sv`: Mirlo's own code, Apache-2.0 (`LICENSE-APACHE-2.0`).
- `sdr_phy.sv`: port of LiteX's SDRAM PHY, BSD 2-Clause (`LICENSE-LITEX-BSD-2-CLAUSE`).
  `LICENSE-LITEX-BSD-2-CLAUSE` is LiteX's upstream `LICENSE` file verbatim
  (SHA-256 `8371c1e1e72db0c21eba5acfec4f4f8597dc8555bd282b2a35ccbbde992675c5`,
  fetched from enjoy-digital/litex master).

Not yet adapted for the Pocket PS1 wrapper:
- The PS1 side needs 16-bit word addressing and 128-bit returns; these modules use
  24-bit word addresses and 32-bit words.
- Clock ratio: these modules assume sys = 62.832 MHz with sys2x pads. Retime
  for the Pocket PLL outputs before use.
- `sdr_phy.sv` uses Altera `ALTDDIO_OUT` (Quartus-only). Simulation needs the
  `VERILATOR` alternative branch or a behavioral model.
