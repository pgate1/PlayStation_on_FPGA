#!/usr/bin/env bash
# Run the bounded Pocket HDL regressions with Icarus Verilog.
#
# Usage: tools/pocket/run_regressions.sh [LOG_DIR]
#
# Builds each bench in a temporary directory, keeps per-test logs in LOG_DIR
# (default: a new temporary directory, printed at the end), and exits nonzero
# if any compile or simulation step fails. No waveforms are dumped.
# Covers isolated behavioral benches only; not a full-system or hardware test.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Check tools before creating any files, so an empty PATH is reported cleanly.
for tool in iverilog vvp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found in PATH: $tool" >&2
        exit 2
    fi
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pocket_regress.XXXXXX")" || exit 2
LOG_DIR="${1:-$WORK/logs}"
mkdir -p "$LOG_DIR" || exit 2

failures=0
run_test() {
    local name="$1"; shift
    local log="$LOG_DIR/$name.log"
    echo "== $name"
    if ! "$@" > "$log" 2>&1; then
        echo "   FAIL (exit status or compile error), log: $log"
        failures=$((failures + 1))
        return
    fi
    if grep -q '^PASS' "$log"; then
        echo "   PASS: $(grep -m1 '^PASS' "$log")"
    else
        echo "   FAIL (no PASS line), log: $log"
        failures=$((failures + 1))
    fi
}

cd "$ROOT" || exit 2

# Memory frontend at the documented parameter sets (see docs/POCKET_IMPLEMENTATION.md).
MEM_SRC=(-c Pocket/rtl/psx_mem.f Pocket/tb/tb_psx_mem.sv)
mem_params=(
    "default:"
    "min:-Ptb_psx_mem.N=1 -Ptb_psx_mem.URGENT_MAX=0 -Ptb_psx_mem.TAGW=1"
    "wide:-Ptb_psx_mem.N=7 -Ptb_psx_mem.URGENT_MAX=1 -Ptb_psx_mem.TAGW=5"
)
for entry in "${mem_params[@]}"; do
    label="${entry%%:*}"
    # shellcheck disable=SC2086
    params="${entry#*:}"
    out="$WORK/tb_psx_mem_$label.vvp"
    # shellcheck disable=SC2086
    run_test "psx_mem_$label" sh -c \
        "iverilog -g2012 -s tb_psx_mem $params -o '$out' ${MEM_SRC[*]} && vvp -n '$out' +seed=3 +cycles=6000"
done

out="$WORK/tb_ram.vvp"
run_test ram_320x240x15_dp sh -c \
    "iverilog -g2012 -s tb_ram_320x240x15_dp -o '$out' Pocket/rtl/ram_320x240x15_dp.sv Pocket/tb/tb_ram_320x240x15_dp.sv && vvp -n '$out' +seed=3"

out="$WORK/tb_sram.vvp"
run_test sram_ctrl sh -c \
    "iverilog -g2012 -s tb_sram_ctrl -o '$out' Pocket/rtl/sram_ctrl.sv Pocket/tb/tb_sram_ctrl.sv && vvp -n '$out' +seed=3 +ops=4000"

echo
echo "Logs: $LOG_DIR"
if [ "$failures" -ne 0 ]; then
    echo "RESULT: $failures regression(s) failed"
    exit 1
fi
echo "RESULT: all regressions passed"
exit 0
