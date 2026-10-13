// tb_clip.sv -- 21-bit -> 16-bit saturation bench (Pocket/audio, P05).
//
// 1. pocket_audio_sat21 exhaustively over all 2^21 signed inputs against
//    clip(x, -32768, 32767); named extremes are listed explicitly.
// 2. Through the resampler: extreme constants and a full-scale alternating
//    (+max, -max) sequence; every output must equal the exact integer model
//    of the interpolator applied to the clipped inputs and stay in range
//    (no wrap at the interpolation step either).
// Mutation: -DPA_MUT_WRAP (truncation instead of clipping) must FAIL.
`timescale 1ns/1ps
`default_nettype none

module tb_clip;
    // ---------------- part 1: combinational, exhaustive ----------------
    logic signed [20:0] x;
    wire  signed [15:0] y;
    pocket_audio_sat21 u_sat (.x(x), .y(y));

    function automatic int clip(input int v);
        return v > 32767 ? 32767 : (v < -32768 ? -32768 : v);
    endfunction

    int errors = 0, n_exh = 0, n_named = 0, n_rs = 0, n_in = 0;
    int named [12] = '{-1048576, -1048575, -65536, -32769, -32768, -32767,
                       -1, 0, 1, 32767, 32768, 1048575};

    // ---------------- part 2: resampler path ----------------
    logic clk = 1'b0, rst = 1'b1, stb = 1'b0;
    logic signed [20:0] in_l = '0, in_r = '0;
    wire  out_valid, busy_drop;
    wire  signed [15:0] out_l, out_r;
    always #10 clk = ~clk;
    pocket_audio_resampler dut (
        .clk(clk), .rst(rst), .smp_stb(stb), .in_l(in_l), .in_r(in_r),
        .out_valid(out_valid), .out_l(out_l), .out_r(out_r), .busy_drop(busy_drop)
    );

    // exact integer model of the interpolator (offset binary, round half up)
    int m_prev_l = 0, m_curr_l = 0, m_prev_r = 0, m_curr_r = 0, m_ph = 0;
    int exp_l [$], exp_r [$];
    function automatic int interp(input int p, input int c, input int ph);
        int up, uc;
        up = p + 32768; uc = c + 32768;
        return (up * 160 + (uc - up) * ph + 80) / 160 - 32768;   // numerator >= 0
    endfunction
    task automatic model_push(input int xl, input int xr);
        m_prev_l = m_curr_l; m_curr_l = clip(xl);
        m_prev_r = m_curr_r; m_curr_r = clip(xr);
        while (m_ph < 160) begin
            exp_l.push_back(interp(m_prev_l, m_curr_l, m_ph));
            exp_r.push_back(interp(m_prev_r, m_curr_r, m_ph));
            m_ph += 147;
        end
        m_ph -= 160;
    endtask

    always @(posedge clk) if (out_valid) begin
        int el, er;
        if (exp_l.size() == 0) begin
            $display("ERROR: unexpected output"); errors++;
        end else begin
            el = exp_l.pop_front(); er = exp_r.pop_front();
            if (out_l != el || out_r != er) begin
                if (errors < 8) $display("ERROR: resampler out (%0d,%0d) expected (%0d,%0d)", out_l, out_r, el, er);
                errors++;
            end
            n_rs++;
        end
    end

    task automatic feed(input int xl, input int xr);
        model_push(xl, xr);
        n_in++;
        in_l <= 21'(xl); in_r <= 21'(xr);
        stb <= 1'b1; @(posedge clk); stb <= 1'b0;
        repeat (23) @(posedge clk);
    endtask

    initial begin
        // part 1
        for (int v = -1048576; v <= 1048575; v++) begin
            x = 21'(v);
            #1;
            if (int'(y) != clip(v)) begin
                if (errors < 8) $display("ERROR: sat21(%0d) = %0d, expected %0d", v, y, clip(v));
                errors++;
            end
            n_exh++;
        end
        foreach (named[i]) begin
            x = 21'(named[i]); #1;
            $display("INFO: sat21(%0d) = %0d", named[i], y);
            if (int'(y) != clip(named[i])) errors++;
            n_named++;
        end

        // part 2
        repeat (3) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);
        repeat (20) feed(-1048576, 1048575);         // 21-bit extremes
        repeat (20) feed(1048575, -1048576);
        repeat (20) feed(32768, -32769);              // just outside 16 bits
        repeat (20) feed(-32768, 32767);              // exact 16-bit limits
        for (int k = 0; k < 400; k++)                 // full-scale alternation
            if (k % 2) feed(1048575, -1048576); else feed(-1048576, 1048575);
        for (int k = 0; k < 400; k++)                 // 17..21-bit magnitude sweep
            feed((k % 2 ? 1 : -1) * (32000 + k * 2500), (k % 2 ? -1 : 1) * (32000 + k * 2400));
        repeat (40) @(posedge clk);
        if (exp_l.size() != 0) begin $display("ERROR: %0d outputs missing", exp_l.size()); errors++; end

        if (errors == 0)
            $display("PASS tb_clip: exhaustive=%0d named=%0d resampler_outputs=%0d (inputs=%0d) errors=0",
                     n_exh, n_named, n_rs, n_in);
        else
            $fatal(1, "FAIL tb_clip: exhaustive=%0d resampler_outputs=%0d errors=%0d", n_exh, n_rs, errors);
        $finish;
    end
endmodule
`default_nettype wire
