#!/usr/bin/env python3
"""Build a standalone SD-card package from a fresh diagnostic Quartus RBF."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from datetime import date
from pathlib import Path

from convert_rbf_r import convert


AUTHOR = "pgate1"
SHORTNAME = "PocketDiag"
VERSION = "0.1.0"
BITSTREAM = "bitstream.rbf_r"


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def package(rbf: Path, output: Path, build_commit: str) -> Path:
    rbf = rbf.resolve()
    output = output.resolve()
    if not rbf.is_file() or rbf.stat().st_size == 0:
        raise ValueError(f"missing or empty RBF: {rbf}")
    if output.exists():
        raise FileExistsError(f"output directory already exists: {output}")

    core_dir = output / "Cores" / f"{AUTHOR}.{SHORTNAME}"
    core_dir.mkdir(parents=True)
    converted = core_dir / BITSTREAM
    convert(rbf, converted)

    documents = {
        "core.json": {"core": {
            "magic": "APF_VER_1",
            "metadata": {
                "platform_ids": ["pocketdiag"], "shortname": SHORTNAME,
                "description": "Pocket video diagnostic", "author": AUTHOR,
                "url": "https://github.com/pgate1/PlayStation_on_FPGA",
                "version": VERSION, "date_release": date.today().isoformat(),
            },
            "framework": {
                "target_product": "Analogue Pocket", "version_required": "1.1",
                "sleep_supported": False,
                "dock": {"supported": True, "analog_output": False},
                "hardware": {"link_port": False, "cartridge_adapter": -1},
            },
            "cores": [{"name": "diagnostic", "id": 0, "filename": BITSTREAM}],
        }},
        "audio.json": {"audio": {"magic": "APF_VER_1"}},
        "data.json": {"data": {"magic": "APF_VER_1", "data_slots": []}},
        "input.json": {"input": {"magic": "APF_VER_1", "controllers": []}},
        "interact.json": {"interact": {"magic": "APF_VER_1", "variables": [], "messages": []}},
        "variants.json": {"variants": {"magic": "APF_VER_1", "variant_list": []}},
        "video.json": {"video": {"magic": "APF_VER_1", "scaler_modes": [{
            "width": 320, "height": 240, "aspect_w": 4, "aspect_h": 3,
            "rotation": 0, "mirror": 0,
        }]}},
    }
    for name, value in documents.items():
        write_json(core_dir / name, value)

    platform_dir = output / "Platforms"
    platform_dir.mkdir(parents=True)
    write_json(platform_dir / "pocketdiag.json", {"platform": {
        "category": "Console", "name": "Pocket Diagnostic", "year": 2026,
        "manufacturer": "pgate1",
    }})

    for path in core_dir.glob("*.json"):
        json.loads(path.read_text(encoding="utf-8"))
    if len(list(core_dir.glob("*.json"))) != 7:
        raise AssertionError("package must contain all seven required JSON definitions")

    archive = output / f"{AUTHOR}.{SHORTNAME}_{VERSION}_{date.today():%Y%m%d}.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as bundle:
        for path in sorted((output / "Cores").rglob("*")) + sorted(platform_dir.rglob("*")):
            if path.is_file():
                bundle.write(path, path.relative_to(output).as_posix())

    report = {
        "quartus_rbf": str(rbf),
        "quartus_rbf_sha256": hashlib.sha256(rbf.read_bytes()).hexdigest(),
        "quartus_rbf_bytes": rbf.stat().st_size,
        "rbf_r_sha256": hashlib.sha256(converted.read_bytes()).hexdigest(),
        "rbf_r_bytes": converted.stat().st_size,
        "converter": "tools/pocket/convert_rbf_r.py",
        "converter_sha256": hashlib.sha256(Path(__file__).with_name("convert_rbf_r.py").read_bytes()).hexdigest(),
        "build_commit": build_commit,
        "quartus": "Quartus Prime Lite 25.1std.0 Build 1129",
        "package": archive.name,
        "package_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
    }
    write_json(output / "diagnostic_package_manifest.json", report)
    return archive


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_rbf", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--build-commit", required=True)
    args = parser.parse_args()
    archive = package(args.input_rbf, args.output_directory, args.build_commit)
    print(f"PASS package {archive}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
