# Pocket diagnostic packaging contract

This records the documented openFPGA packaging procedure and the first
diagnostic package generated from a fresh Quartus build. A local candidate
package exists; the physical Pocket test has **not** run.

## Exact RBF to RBF_R conversion

Analogue's [official packaging guide](https://www.analogue.co/developer/docs/openfpga/packaging-a-core#fpga-bitstream)
defines Quartus `.rbf` as the raw bitstream and APF `.rbf_r` as the same stream
with the bits reversed **within each byte**. For each input byte, reverse bit
positions 7 through 0, write that byte, then continue in the original byte
order. For example, `0x01` becomes `0x80`; `0x96` becomes `0x69`. There is no
byte swapping, word endian conversion, header addition, truncation, padding,
compression, or other stream-level rearrangement in this conversion. The output
keeps the input length. The `.rbf_r` suffix names the converted bytes; renaming
an unchanged `.rbf` does not perform the conversion. The guide explicitly says
`.sof` is for JTAG debugging and is not the packaged format.

The pinned project is open-fpga/core-template revision
[`da3a021b1eaf742604d86d8dc9b33a6666263e6a`](https://github.com/open-fpga/core-template/tree/da3a021b1eaf742604d86d8dc9b33a6666263e6a).
Its `src/fpga/ap_core.qsf` sets `PROJECT_OUTPUT_DIRECTORY output_files`,
`GENERATE_RBF_FILE ON`, device `5CEBA4F23C8`, and top-level project revision
`ap_core`. Thus, after a successful Quartus run using this project, the input
artifact expected for conversion is `output_files/ap_core.rbf`. The first
build produced that file at the expected location. The prepared diagnostic
project inherits those settings. Analogue's guide also recommends enabling
compressed bitstreams to reduce load times. The prepared QSF requests RBF
generation but does not explicitly set `COMPRESS_RBF_FILE`; compression was
not confirmed for this build.

Official documentation specifies the byte transform but does not prescribe a
particular converter executable or CLI. Use a reviewed implementation of that
algorithm and record its source/version or digest with the build evidence. Do
not treat a file copied from the template's `output/bitstream.rbf_r` or the
repository's existing `Pocket/dist/Cores/pgate1.PlayStation/bitstream.rbf_r`
as output from the diagnostic build.

## Core definition and SD layout

Analogue's [core definition file list](https://www.analogue.co/developer/docs/openfpga/core-definition-files)
marks all seven JSON files as required in a core folder: `core.json`,
`audio.json`, `data.json`, `input.json`, `interact.json`, `variants.json`, and
`video.json`. `info.txt` and `icon.bin` are optional. The official
[`core.json` schema](https://www.analogue.co/developer/docs/openfpga/core-definition-files/core-json)
names these fields:

| Object | Fields and constraints relevant to this package |
|---|---|
| `core` | `magic` must be `APF_VER_1`; contains `metadata`, `framework`, and `cores` |
| `metadata` | `platform_ids` is an array (empty means standalone; at most four platforms); `shortname` (max 31 chars), `description` (max 63), `author` (max 31), `url` (max 63), `version` (max 31), and `date_release` (`YYYY-MM-DD`, max 10) |
| `framework` | `target_product` must be `Analogue Pocket`; `version_required` uses a version such as `1.1`; also describes `sleep_supported`, `dock.supported`, `dock.analog_output`, `hardware.link_port`, and `hardware.cartridge_adapter` |
| each `cores` entry | `name` is an optional debug label (max 15); `id` identifies the core; `filename` is the exact bitstream filename (max 15 chars, bit-reversed for APF); at most eight entries |

The pinned template supplies an example value for every field above. Use valid
values for the diagnostic instead of copying the template's example identity.
Each core entry's `filename` must match the RBF_R file exactly.

For a standalone diagnostic package, Analogue documents an empty
`metadata.platform_ids` array as valid. That avoids registering a diagnostic
under PlayStation while its image only displays a test pattern. If the operator
chooses to associate it with a platform instead, set that platform shortname
in `platform_ids` and add `/Platforms/<platform_shortname>.json`; the optional
platform image belongs at `/Platforms/_images/<platform_shortname>.bin`.
Analogue's [platform metadata guide](https://www.analogue.co/developer/docs/openfpga/platform-metadata)
defines the optional platform JSON's `platform` object fields as `category`,
`name`, `manufacturer`, and integer `year` (the strings have documented
maximum lengths). A missing platform JSON does not prevent running, but official docs say
the platform's extra information and future OS features will be unavailable.

The [official SD structure](https://www.analogue.co/developer/docs/openfpga/directories-and-sd-folder-structure)
requires the core folder convention `AuthorName.CoreName`, matching the
`author` and `shortname` values in `core.json`. A package ZIP contains a
snapshot of SD-card paths rooted at the card root, not a wrapping repository
directory. The minimal standalone diagnostic layout is therefore:

```text
Cores/<AuthorName>.<CoreName>/
  core.json
  audio.json
  data.json
  input.json
  interact.json
  variants.json
  video.json
  bitstream.rbf_r
  [info.txt]
  [icon.bin]
```

If using a custom platform, also include `Platforms/<shortname>.json` and any
chosen `Platforms/_images/<shortname>.bin`. Include `Assets/...` only if the
core's data definitions require actual supplied assets. For this diagnostic,
the package generator supplies an empty `data_slots` list and standalone
metadata instead of reusing the PS1 core's BIOS/ROM declarations. The seven
JSON files are parse-checked; formal validation against Analogue's schema and
physical OS recognition remain part of the device test.

Analogue's [packaging guide](https://www.analogue.co/developer/docs/openfpga/packaging-a-core)
allows distributing these SD paths in one ZIP and gives the recommended
archive name pattern `<AuthorName>.<CoreName>_<Version>_<ReleaseDate>.zip`.
The archive name is a recommendation, not the bitstream filename contract.

## What exists in this checkout

| Item | Current evidence | Status for diagnostic package |
|---|---|---|
| Pinned APF project and metadata | Verified cached template at revision `da3a021b1eaf742604d86d8dc9b33a6666263e6a`; QSF enables RBF generation | Available source project |
| Prepared diagnostic project | `Pocket/build/diagnostic-reviewed/`, isolated from the PS1 source tree | Prepared inputs; independent of Quartus outputs |
| Current Quartus `.rbf` from diagnostic | `Pocket/build/diagnostic-quartus-25.1/output_files/ap_core.rbf` | Quartus Lite 25.1std.0 Build 1129; 788,200 bytes; SHA-256 `73a554ddb1196c21b83720b3d40c646bed2d3251f2d7b890b90d98d3fe787a3b` |
| Converted `.rbf_r` from diagnostic | `Pocket/build/diagnostic-package-25.1/Cores/pgate1.PocketDiag/bitstream.rbf_r` | 788,200 bytes; SHA-256 `5ed526b0411cf8e35874a2589ecbaf7e105b4629d3b621bdf896a57de26e0fc3`; byte-reversal conversion verified |
| Diagnostic core definition files | `Pocket/build/diagnostic-package-25.1/Cores/pgate1.PocketDiag/` | Seven required JSON files generated and parse-checked; no BIOS/ROM slots |
| Diagnostic ZIP | `Pocket/build/diagnostic-package-25.1/pgate1.PocketDiag_0.1.0_20261013.zip` | Eight expected SD files; SHA-256 `75f80effaa0e023e4d48aa2bf31bc00e430602b70140b08b6855fbaf13d5f94d`; not loaded on hardware |
| Existing PlayStation package metadata and platform data | `Pocket/dist/Cores/pgate1.PlayStation/` and `Pocket/dist/Platforms/playstation.json` | Present, describes PlayStation; do not reuse as if it describes the diagnostic |
| Existing PlayStation `.rbf_r` and template `.rbf_r` | Both present in source trees | Old/reference artifacts; neither is a new diagnostic build |
| Platform image and dummy asset files | Existing PlayStation platform image and `.bin_dummy` files are present | Not evidence of a diagnostic build; dummy BIOS/ROM are not usable assets |

## Operator checklist for the physical test

Keep these fields blank until the corresponding newly generated evidence exists.

```text
Diagnostic source commit: ______________________________
Prepared project manifest SHA-256: ____________________
Quartus version/build: __________________________________
Quartus compile log path: ______________________________
Quartus result (success/failure): _______________________
Fit/resource report path: ______________________________
TimeQuest timing reports reviewed: _____________________
Fresh output_files/ap_core.rbf path: ____________________
Fresh .rbf SHA-256 and byte count: ______________________
Converter implementation/version or digest: ____________
Converted bitstream.rbf_r path: ________________________
.rbf_r SHA-256 and byte count: __________________________
Conversion length equality confirmed: __________________
Diagnostic core metadata directory: ____________________
core.json filename matches .rbf_r: _____________________
All seven required JSON files present and parseable: ____
Package ZIP path and SHA-256: ___________________________
Pocket model / OS version: ______________________________
Hardware result and evidence path: ______________________
```

Before hardware use, check that the RBF input was produced by the recorded
successful build; verify the converter processes every input byte exactly once,
the `.rbf_r` byte count equals the `.rbf` byte count, and the SD package's
`core.json` filename equals `bitstream.rbf_r`. Review Quartus fit and timing
reports independently. A structurally valid package does not prove fit,
timing closure, Pocket loading, or visible output.

## Official sources

- [Analogue: Packaging a Core, including FPGA Bitstreams and SD ZIP contents](https://www.analogue.co/developer/docs/openfpga/packaging-a-core)
- [Analogue: Core Definition Files](https://www.analogue.co/developer/docs/openfpga/core-definition-files)
- [Analogue: `core.json` field definitions](https://www.analogue.co/developer/docs/openfpga/core-definition-files/core-json)
- [Analogue: Directories and SD Folder Structure](https://www.analogue.co/developer/docs/openfpga/directories-and-sd-folder-structure)
- [Analogue: Platform Metadata](https://www.analogue.co/developer/docs/openfpga/platform-metadata)
- [Pinned open-fpga/core-template revision](https://github.com/open-fpga/core-template/tree/da3a021b1eaf742604d86d8dc9b33a6666263e6a)
