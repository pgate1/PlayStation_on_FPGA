#!/usr/bin/env python3
"""Convert a raw Quartus RBF to Analogue's byte-bit-reversed RBF_R format."""

from __future__ import annotations

import argparse
from pathlib import Path


BIT_REVERSE = bytes(int(f"{value:08b}"[::-1], 2) for value in range(256))


def convert(source: Path, destination: Path) -> None:
    source = source.resolve()
    destination = destination.resolve()
    if source == destination:
        raise ValueError("input and output paths must be different")
    data = source.read_bytes()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data.translate(BIT_REVERSE))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_rbf", type=Path)
    parser.add_argument("output_rbf_r", type=Path)
    args = parser.parse_args()
    convert(args.input_rbf, args.output_rbf_r)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
