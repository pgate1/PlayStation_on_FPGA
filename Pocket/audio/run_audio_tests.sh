#!/usr/bin/env bash
# Pocket/audio bench runner (P05).  Usage:
#   Pocket/audio/run_audio_tests.sh [test ...]
# Without arguments every test runs (sequentially; ~15 min with Icarus 13).
# Output directory: $AUDIO_TB_OUT (default: a new mktemp -d directory).
# Each test prints "<name> exit=<status> <PASS/FAIL line>".  Mutation tests
# (mut_*) are expected to FAIL; the runner reports "mutation detected" for
# them when the simulator exits non-zero with a FAIL line.
# Overall exit status is 0 only if every normal test passed and every
# mutation was detected.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
A="$ROOT/Pocket/audio"
OUT="${AUDIO_TB_OUT:-$(mktemp -d)}"
mkdir -p "$OUT"
RTL="$A/pocket_audio_out.sv"
overall=0

ivl() {   # ivl <name> <tb top> <tb file> "<iverilog defines>" "<plusargs>" <expect pass|fail>
    local name=$1 top=$2 tb=$3 defs=$4 args=$5 want=$6
    # shellcheck disable=SC2086
    if ! iverilog -g2012 $defs -o "$OUT/$name.vvp" -s "$top" "$RTL" "$A/$tb" > "$OUT/$name.build.log" 2>&1; then
        echo "$name build FAILED (see $OUT/$name.build.log)"; overall=1; return
    fi
    # shellcheck disable=SC2086
    vvp -n "$OUT/$name.vvp" $args > "$OUT/$name.log" 2>&1
    local st=$?
    local line
    line=$(grep -E "^(PASS|FATAL|FAIL)|FAIL tb_" "$OUT/$name.log" | head -1)
    if [ "$want" = pass ]; then
        if [ $st -eq 0 ] && grep -q "^PASS" "$OUT/$name.log"; then echo "$name exit=$st $line"
        else echo "$name exit=$st UNEXPECTED: $line"; overall=1; fi
    else
        if [ $st -ne 0 ] && grep -q "FAIL tb_" "$OUT/$name.log"; then echo "$name exit=$st mutation detected: $line"
        else echo "$name exit=$st MUTATION NOT DETECTED: $line"; overall=1; fi
    fi
}

run() {
    case $1 in
    lint)
        local st=0
        for m in 0 1 2; do
            verilator --lint-only -Wall --top-module pocket_audio_out -GSAMPLE_SRC=$m "$RTL" > "$OUT/lint$m.log" 2>&1 || st=1
        done
        echo "lint exit=$st (verilator --lint-only -Wall, SAMPLE_SRC=0/1/2)"; [ $st -eq 0 ] || overall=1 ;;
    resampler)      ivl resampler      tb_resampler tb_resampler.sv "" "" pass ;;
    mut_ratio)      ivl mut_ratio      tb_resampler tb_resampler.sv "-DRATIO=148" "" fail ;;
    clip)           ivl clip           tb_clip      tb_clip.sv "" "" pass ;;
    mut_wrap)       ivl mut_wrap       tb_clip      tb_clip.sv "-DPA_MUT_WRAP" "" fail ;;
    i2s_nominal)    ivl i2s_nominal    tb_i2s_cdc tb_i2s_cdc.sv "" "+ms=40" pass ;;
    i2s_jitter)     ivl i2s_jitter     tb_i2s_cdc tb_i2s_cdc.sv "" "+ms=40 +jit=1500 +phase=777 +seed=7" pass ;;
    i2s_ppm_pos)    ivl i2s_ppm_pos    tb_i2s_cdc tb_i2s_cdc.sv "" "+ms=40 +ppm=200 +jit=500 +phase=9000 +seed=3" pass ;;
    i2s_ppm_neg)    ivl i2s_ppm_neg    tb_i2s_cdc tb_i2s_cdc.sv "" "+ms=40 +ppm=-200 +jit=500 +phase=1500 +seed=4" pass ;;
    i2s_run33)      ivl i2s_run33      tb_i2s_cdc tb_i2s_cdc.sv "-DSRC=1" "+ms=40 +phase=5000 +jit=300 +seed=5" pass ;;
    i2s_underflow)  ivl i2s_underflow  tb_i2s_cdc tb_i2s_cdc.sv "" "+ms=40 +ppm=-20000 +expect=udf +seed=6" pass ;;
    i2s_overflow)   ivl i2s_overflow   tb_i2s_cdc tb_i2s_cdc.sv "" "+ms=40 +ppm=20000 +expect=ovf +seed=8" pass ;;
    mut_swap_tb)    ivl mut_swap_tb    tb_i2s_cdc tb_i2s_cdc.sv "-DTB_SWAP_INPUTS" "+ms=40" fail ;;
    mut_swap_rtl)   ivl mut_swap_rtl   tb_i2s_cdc tb_i2s_cdc.sv "-DPA_MUT_SWAP" "+ms=40" fail ;;
    *) echo "unknown test $1"; overall=1 ;;
    esac
}

if [ $# -eq 0 ]; then
    set -- lint resampler mut_ratio clip mut_wrap i2s_nominal i2s_jitter i2s_ppm_pos \
           i2s_ppm_neg i2s_run33 i2s_underflow i2s_overflow mut_swap_tb mut_swap_rtl
fi
echo "logs: $OUT"
for t in "$@"; do run "$t"; done
echo "overall exit=$overall"
exit $overall
