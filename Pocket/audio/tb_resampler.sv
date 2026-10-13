// tb_resampler.sv -- 44.1 -> 48 kHz resampler bench (Pocket/audio, P05).
//
// Checks
//   1. sample accounting after EVERY input: outputs == ceil(160*(k+1)/147)
//      (exact rational progression, no drift); 44100 in -> 48000 out;
//   2. every output against a double-precision linear-interpolation model:
//      |y_hw - y_ref| <= 0.5 LSB, ties rounded up (i.e. y_hw is the
//      correctly rounded value of the exact model);
//   3. informational: error of the linear interpolator against the ideal
//      continuous sine at the 48 kHz output instants (quality limit).
// Plusargs: +nin=<inputs> (default 44100), +nocheck (count-only, long runs),
//           +gap=<clk cycles between strobes> (default 24, minimum 17).
// Mutation: -DRATIO=148 (wrong ratio) must FAIL.
`timescale 1ns/1ps
`default_nettype none
`ifndef RATIO
`define RATIO 147
`endif

module tb_resampler;
    logic clk = 1'b0, rst = 1'b1, stb = 1'b0;
    logic signed [20:0] in_l = '0, in_r = '0;
    wire  out_valid, busy_drop;
    wire  signed [15:0] out_l, out_r;

    always #10 clk = ~clk;    // 50 MHz

    pocket_audio_resampler #(.RATIO_NUM(`RATIO)) dut (
        .clk(clk), .rst(rst), .smp_stb(stb), .in_l(in_l), .in_r(in_r),
        .out_valid(out_valid), .out_l(out_l), .out_r(out_r), .busy_drop(busy_drop)
    );

    localparam int MAXN  = 44100;
    localparam int MAXO  = 48001;
    localparam real PI   = 3.14159265358979323846;
    localparam real FS   = 44100.0;

    int  nin, gap;
    bit  check;
    longint nout;
    int  errors, drops, acct_err, tol_err;
    // A[0] = x[-1] = 0 (reset), A[k+1] = sat16(x[k])
    real Al[0:MAXN], Ar[0:MAXN];
    real ideal_l[0:MAXN];           // ideal continuous value parameters per region
    int  yl[0:MAXO-1], yr[0:MAXO-1];
    real max_abs_err;

    function automatic int sat16(input longint v);
        if (v > 32767) return 32767;
        if (v < -32768) return -32768;
        return int'(v);
    endfunction

    // stimulus definition (left: three tone regions, right: sawtooth ramp)
    function automatic real tone_l(input real k);   // ideal signal at input index k (real)
        if (k < 14700.0)      return 30000.0 * $sin(2.0*PI*1000.0*k/FS);
        else if (k < 29400.0) return 20000.0 * $sin(2.0*PI*10000.0*k/FS);
        else                  return 50000.0 * $sin(2.0*PI*1000.0*k/FS);   // clips
    endfunction
    function automatic longint ramp_r(input int k);
        return longint'(((k * 1237) % 98304) - 49152);   // also exceeds 16 bits
    endfunction

    always @(posedge clk) begin
        if (out_valid) begin
            if (check && nout < MAXO) begin yl[nout] = out_l; yr[nout] = out_r; end
            nout = nout + 1;
        end
        if (busy_drop) drops = drops + 1;
    end

    // quality statistics against the ideal continuous sine
    real sig1, err1, sig10, err10;

    initial begin
        longint expect_cnt;
        real pos, f, ref_l, ref_r, d, t;
        longint i;
        if (!$value$plusargs("nin=%d", nin)) nin = 44100;
        if (!$value$plusargs("gap=%d", gap)) gap = 24;
        check = !$test$plusargs("nocheck");
        if (check && nin > MAXN) begin $display("FAIL: +nin too large for check mode"); $finish; end
        nout = 0; errors = 0; drops = 0; acct_err = 0; tol_err = 0; max_abs_err = 0.0;
        sig1 = 0.0; err1 = 0.0; sig10 = 0.0; err10 = 0.0;
        if (check) begin Al[0] = 0.0; Ar[0] = 0.0; end

        repeat (4) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);

        for (int k = 0; k < nin; k++) begin
            longint xl, xr;
            xl = longint'($rtoi(tone_l(k) + (tone_l(k) >= 0.0 ? 0.5 : -0.5)));
            xr = ramp_r(k % 1000003);
            if (check) begin
                Al[k+1] = sat16(xl);
                Ar[k+1] = sat16(xr);
            end
            in_l <= 21'(xl);
            in_r <= 21'(xr);
            stb  <= 1'b1;
            @(posedge clk);
            stb  <= 1'b0;
            repeat (gap - 1) @(posedge clk);
            // all outputs for this input are out: exact accounting
            expect_cnt = (160 * longint'(k + 1) + 146) / 147;
            if (nout != expect_cnt) begin
                if (acct_err < 5) $display("ERROR: after %0d inputs got %0d outputs, expected %0d", k+1, nout, expect_cnt);
                acct_err++;
            end
        end
        repeat (32) @(posedge clk);

        if (nin == 44100 && nout != 48000) begin
            $display("ERROR: 44100 inputs gave %0d outputs, expected 48000", nout);
            errors++;
        end
        // independent of the RTL constant: expected count from the true ratio
        if (nout != (160 * longint'(nin) + 146) / 147) begin
            $display("ERROR: %0d inputs gave %0d outputs, expected %0d", nin, nout, (160 * longint'(nin) + 146) / 147);
            errors++;
        end

        if (check) begin
            for (longint n = 0; n < nout && n < MAXO; n++) begin
                i   = (n * 147) / 160;
                f   = real'((n * 147) % 160) / 160.0;
                ref_l = Al[i] + (Al[i+1] - Al[i]) * f;
                ref_r = Ar[i] + (Ar[i+1] - Ar[i]) * f;
                d = real'(yl[n]) - ref_l; if (d < 0) d = -d;
                if (d > max_abs_err) max_abs_err = d;
                if (d > 0.5 || (d == 0.5 && real'(yl[n]) < ref_l)) begin
                    if (tol_err < 5) $display("ERROR: L out %0d = %0d ref %f", n, yl[n], ref_l);
                    tol_err++;
                end
                d = real'(yr[n]) - ref_r; if (d < 0) d = -d;
                if (d > max_abs_err) max_abs_err = d;
                if (d > 0.5 || (d == 0.5 && real'(yr[n]) < ref_r)) begin
                    if (tol_err < 5) $display("ERROR: R out %0d = %0d ref %f", n, yr[n], ref_r);
                    tol_err++;
                end
                // ideal continuous signal at the output instant (input index pos-1)
                pos = real'(n) * 147.0 / 160.0;
                t   = pos - 1.0;
                if (t > 100.0 && t < 14600.0) begin
                    sig1 += tone_l(t) * tone_l(t);
                    err1 += (real'(yl[n]) - tone_l(t)) * (real'(yl[n]) - tone_l(t));
                end else if (t > 14800.0 && t < 29300.0) begin
                    sig10 += tone_l(t) * tone_l(t);
                    err10 += (real'(yl[n]) - tone_l(t)) * (real'(yl[n]) - tone_l(t));
                end
            end
            $display("INFO: linear interpolation vs ideal sine: 1 kHz SNR %0.1f dB, 10 kHz SNR %0.1f dB",
                     10.0 * $log10(sig1 / err1), 10.0 * $log10(sig10 / err10));
            $display("INFO: max |hw - double ref| = %0.4f LSB", max_abs_err);
        end

        errors += acct_err + tol_err + drops;
        if (errors == 0)
            $display("PASS tb_resampler: mode=%0s inputs=%0d outputs=%0d per-input-accounting-errors=0 value-checks=%0d (tol 0.5 LSB) busy_drops=0",
                     check ? "full" : "count-only", nin, nout, check ? 2 * nout : 0);
        else
            $fatal(1, "FAIL tb_resampler: inputs=%0d outputs=%0d accounting_err=%0d tol_err=%0d drops=%0d errors=%0d",
                   nin, nout, acct_err, tol_err, drops, errors);
        $finish;
    end
endmodule
`default_nettype wire
