#!/usr/bin/env bash
# Fetches the Analogue APF shell files from open-fpga/core-template at a pinned revision.
# The files are under Analogue's Software License Agreement, not MIT, so they are NOT
# committed here. They go to Pocket/build/apf/ (gitignored) and are verified by SHA-256.
# Usage: tools/apf/fetch_apf.sh [output_dir]   (default: Pocket/build/apf)
set -euo pipefail

REV=da3a021b1eaf742604d86d8dc9b33a6666263e6a
BASE="https://raw.githubusercontent.com/open-fpga/core-template/$REV/src/fpga"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/Pocket/build/apf}"

# "<path under src/fpga>  <sha256>"
FILES='
apf/apf_constraints.sdc 18b72957181178b046c2f27711190cb426482edcd7b58fcda9cfea27e855dd2e
apf/apf_top.v 6c24aa45a3dab52d8b86944cdd90330aa74cfdcd62e2d43e39d33d4791d173c7
apf/apf.qip 94af53185dde4d51ef30e75bb1ec8df672126742af36399bd62f4efb3a84b26a
apf/build_id_gen.tcl 6279533fec80081e3c91884e1cc5df853b2a716df0b573636147f3420aace996
apf/build_id.mif 3ef497ff9c6bd44ad96c936a2ee3bcf8e624f8b74ef4b37bedd10e98f0e91ee3
apf/common.v c1615e2c6c12b111537f6ca11e826e5061eb91f405e349bdc649a17b48e24d4e
apf/io_bridge_peripheral.v fb9c13e0311ac6b01019898d0ca7786f370228380356fe618fc2b473f2add17d
apf/io_pad_controller.v 70cda74af63d3baa53f87473e1d9e2d524ea305b299a3f832d6c1292771a305e
apf/mf_datatable.qip 8d4fac9c708f86c426e5241055d8000063e16dbe9b5c414f320a8b24c44a0632
apf/mf_datatable.v e2cc2e33ccc22b9a8be3c426141848e0ea7800abb45ce55530eebe17dd23ffd7
apf/mf_ddio_bidir_12.qip f0ed4e73a07d734115bbde6501b43fe5878a7409f9b3b68bb4c7e0424b31b42e
apf/mf_ddio_bidir_12.v 31c8b62114d7bc916104a6199d919d9e2235a164aba518360b339867a08426aa
core/core_bridge_cmd.v e6e0185218b3a63799db0f80085b0f4570c003c5f2197e8c9b8a1b1350f733fe
'

if command -v sha256sum >/dev/null 2>&1; then
    sha() { sha256sum "$1" | cut -d' ' -f1; }
else
    sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi

mkdir -p "$OUT"
fail=0
while read -r rel want; do
    [ -n "$rel" ] || continue
    dst="$OUT/$rel"
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ] && [ "$(sha "$dst")" = "$want" ]; then
        echo "ok (cached)  $rel"
        continue
    fi
    curl -sSfL --retry 5 -o "$dst.part" "$BASE/$rel"
    got="$(sha "$dst.part")"
    if [ "$got" != "$want" ]; then
        echo "SHA-256 MISMATCH: $rel" >&2
        echo "  expected $want" >&2
        echo "  got      $got" >&2
        rm -f "$dst.part"
        fail=1
        continue
    fi
    mv "$dst.part" "$dst"
    echo "ok           $rel"
done <<EOF
$FILES
EOF

[ "$fail" -eq 0 ] || { echo "APF fetch failed" >&2; exit 1; }
echo "APF files at $OUT (core-template $REV)"
