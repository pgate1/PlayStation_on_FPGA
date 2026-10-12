# Building the prepared Pocket diagnostic with Quartus

## What is ready, and what is not

`Pocket/build/diagnostic-reviewed/` is a separate APF diagnostic project. Its
QPF revision is `ap_core`; the QSF selects top `apf_top`, Cyclone V device
`5CEBA4F23C8`, and includes the APF pin, PLL, and SDC sources. The project was
prepared from reference revision `da3a021b1eaf742604d86d8dc9b33a6666263e6a`.
Its QSF records that the reference project was last built with Quartus Prime
Lite **18.1.1 Build 646**. The reference device/package and Lite edition are
compatible in principle: Altera's archived Lite 18.1 Linux page lists the
Cyclone V support package, while the project QSF names the exact target.
[Altera download page for Quartus Lite 18.1 on Linux](https://www.altera.com/downloads/fpga-development-tools/quartus-prime-lite-edition-design-software-version-18-1-linux)

This establishes tool/device availability, not build success. `quartus_sh` is
not available in the current workspace, and the prepared project's manifest
still says compile `not-run`, timing review `pending`, and Pocket hardware
`not-run`. No bitstream, fit result, or timing result is established here.
The preparation utility prints the required compile entrypoint; this document
does not add an APF wrapper or alter the prepared project.

## Recommended host: x86-64 Linux self-hosted machine

The most practical first build is on a persistent x86-64 Linux workstation or
VM with at least **40 GB free disk space before installation**. That is a
planning allowance, not an Intel minimum: Altera lists 14 GB minimum for the
Lite installation, and its archived download page lists a 6.2 GB Quartus 18.1
Linux package, a 1.1 GB Cyclone V package, and a 5.4 GB 18.1 Update 1 package.
The base combined package is described as including device support; if using
individual downloads, select and verify the matching Cyclone V support before
building. The 40 GB allowance accounts for the installer/update downloads,
temporary extraction, installed tool, and generated project database/reports.
[Altera's archived package sizes and checksums](https://www.altera.com/downloads/fpga-development-tools/quartus-prime-lite-edition-design-software-version-18-1-linux)

Use the archived 18.1 Linux package plus Update 1 to match the QSF's recorded
18.1.1 release. Altera currently lists these Linux downloads and SHA-1 values:

| Package | Download size | Published SHA-1 |
|---|---:|---|
| `Quartus-lite-18.1.0.625-linux.tar` | 6.2 GB | `23ef7030b1153c3f4bd20b7b320847079e3235fa` |
| `cyclonev-18.1.0.625.qdz` | 1.1 GB | `be21e885ffd70321d926dbe269ee8c2ef7ad615e` |
| `QuartusSetup-18.1.1.646-linux.run` | 5.4 GB | `d5d69bbf0de659fc7fa63f66a7715f26d288c35c` |

The base tar is labelled as including device support; the separate Cyclone V
package is listed on the same page for individual-package installs. Avoid
installing duplicate device files. Download only from Altera's official page,
verify the selected package checksums, and follow its Linux installation
instructions. The page documents running the update `.run` after the base
Quartus install. It offers both combined and individual-package paths; exact
installer flags and unattended-install behavior have **not** been tested for
these old packages. Use the documented installer flow and handle any GUI/CLI,
license-agreement, or first-run prompts interactively during machine setup.
The Lite edition does not require a Quartus license file; download consent and
the applicable software terms still need to be handled by the person
provisioning the host. Do not put installer credentials or license files in
the repository. [Intel's Lite licensing statement](https://www.intel.com/content/www/us/en/docs/programmable/683472/24-3/design-suite-overview.html)

Quartus 18.1 is an older release. Select a 64-bit Linux distribution supported
by that release's own `readme.txt` and installation notes; do not assume that
the latest GitHub Ubuntu image is ABI-compatible just because it is Linux.
The current Intel installation guide lists Linux prerequisites and recommends
checking the selected release's system requirements, but its current OS list
does not establish 18.1 compatibility.
[Intel FPGA installation and licensing guide](https://www.intel.com/content/www/us/en/support/programmable/licensing/installation-and-licensing.html)

Once installed and initialized, add the selected install's `quartus/bin` to
`PATH`. From the repository root, run the local input preflight, then confirm
the actual binary/version and compile from the project directory:

```sh
python3 tools/pocket/check_diagnostic_project.py Pocket/build/diagnostic-reviewed
command -v quartus_sh
quartus_sh --version
cd Pocket/build/diagnostic-reviewed
quartus_sh --flow compile ap_core
```

Run `quartus_sh --flow compile ap_core` from the directory containing
`ap_core.qpf`. The QSF enables RBF generation. The command's first run is the
first actual synthesis/fit measurement; no runtime estimate is available before
that run. For planning, reserve a half-day for initial package download,
installation, compatibility adjustments, a full compile, and evidence review.
That is a scheduling allowance, not a measured Quartus duration.

## GitHub Actions option

A standard GitHub-hosted runner is a poor first-build target. Current standard
Linux runners provide 14 GB SSD; public runners have 4 CPUs/16 GB RAM and
private-repository runners have 2 CPUs/8 GB RAM. Fourteen GB is equal to the
published minimum installed Lite footprint, before checkout, installer files,
temporary extraction, or Quartus output. GitHub-hosted jobs also have a six-hour
execution limit. [GitHub runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [Actions execution limits](https://docs.github.com/en/actions/reference/limits)

For an ephemeral hosted build, a larger Ubuntu x64 runner offers 75 GB on the
smallest listed Linux size; larger sizes provide additional storage. Larger
runners require a GitHub Team or Enterprise Cloud organization, and their job
time limit is still six hours. A prebuilt custom image could avoid a lengthy
install each run, but whether Quartus may be placed in such an image depends on
the applicable software terms and account setup; neither is established here.
[GitHub larger runner reference](https://docs.github.com/en/enterprise-cloud@latest/actions/reference/runners/larger-runners)

For any CI build, first provision a runner manually with the pinned Lite 18.1.1
and Cyclone V files, confirm it can use the project without interactive
prompts, and measure both installation and compile wall time. Only then decide
whether to automate installation or cache a preinstalled image. Installer CLI
flags, dependency packages on a particular runner image, and license/EULA
prompt behavior are **unverified**. Self-hosted x64 Linux runners are supported
by GitHub Actions, but the host still must satisfy Quartus 18.1's own OS and
runtime requirements.
[GitHub self-hosted runner requirements](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)

## Build evidence to retain

Keep an immutable copy of the prepared project and record its git commit and
`diagnostic_build.json` hashes before compilation. Archive the tool-version
output, complete compile log, and Quartus-generated `output_files/` and
`db/reports/` trees. The evidence package must include the generated `.sof`,
the `.rbf` if Quartus produces it, the fit/resource summary, pin and I/O report,
clock report, and TimeQuest setup/hold timing reports. Record warnings and
errors; inspect unconstrained paths, clock relationships, and the inherited
SDC clock-group exceptions instead of treating a successful fitter exit as
timing signoff. Hash the final report bundle and bitstream(s).

The hardware gate remains separate: fitting and timing evidence do not prove
that a Pocket loads the resulting image or displays the bars/responds to its
button. Record physical testing separately using
[the diagnostic test card](POCKET_DIAGNOSTIC_TEST.md). The diagnostic is not a
PS1 game or an FPS result.
