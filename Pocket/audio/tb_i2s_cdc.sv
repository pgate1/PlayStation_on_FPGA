// tb_i2s_cdc.sv -- end-to-end bench for pocket_audio_out (Pocket/audio, P05):
// core clock (50 MHz) -> resampler -> async FIFO -> clk_74a (74.25 MHz) ->
// I2S, decoded back by a receiver model that sees only MCLK, LRCK and DAC.
//
// Receiver model (what the Pocket gets: MCLK, LRCK, DAC; SCLK = MCLK/4):
//   the first MCLK rising edge that sees a new LRCK level is E1; the
//   receiver's SCLK rising edges are E2, E6, E10, ... (bit slots 0..31).
//   Slot 0 is the I2S one-bit delay, slots 1..16 carry the 16-bit word MSB
//   first, slots 17..31 are ignored.  LRCK low = left, high = right.
//   DAC must be identical at E1, E2 and E3 of every slot (data valid for the
//   whole SCLK high phase around the sampling edge).
// Expected samples come from the testbench's own integer model of the
// interpolator, fed with the values the testbench drove (not DUT internals),
// so a swapped channel or wrong ratio is caught.
//
// Plusargs
//   +ms=<simulated ms>        default 60
//   +ppm=<core clock offset>  default 0 (positive: core faster)
//   +jit=<ps>                 peak uniform phase jitter on every edge of both clocks
//   +phase=<ps>               initial clk_74a phase offset
//   +seed=<n>
//   +expect=exact|udf|ovf     default exact
// Defines
//   -DSRC=2 (default, internal 50 MHz accumulator) or -DSRC=1 (run33 from a
//   DDS_50to33868800-equivalent in the testbench)
//   -DTB_SWAP_INPUTS          mutation: L/R wired crossed to the DUT (must FAIL)
//   -DPA_MUT_SWAP             mutation inside the RTL serializer (must FAIL)
`timescale 1ns/1ps
`default_nettype none
`ifndef SRC
`define SRC 2
`endif

module tb_i2s_cdc;
    // ---------------- clocks ----------------
    logic clk_core = 1'b0, clk_74a = 1'b0;
    real  ms, ppm, jit_ns, phase_ns;
    int   seed, seed0;
    string expect_mode;

    function automatic real jitter();
        int r;
        if (jit_ns == 0.0) return 0.0;
        r = $random(seed);
        if (r < 0) r = -r;
        return jit_ns * (2.0 * (real'(r % 1000001) / 1000000.0) - 1.0);
    endfunction

    // edges are scheduled from absolute time: no accumulated rounding drift
    initial begin : gen_core
        real half, t;
        longint n;
        #10;   // after the plusargs are read
        half = 10.0 / (1.0 + ppm * 1.0e-6);
        n = 1;
        forever begin
            t = 50.0 + real'(n) * half + jitter();
            if (t > $realtime) #(t - $realtime);
            clk_core = ~clk_core;
            n++;
        end
    end
    initial begin : gen_aud
        real half, t;
        longint n;
        #10;   // after the plusargs are read
        half = 1000.0 / 74.25 / 2.0;
        n = 1;
        forever begin
            t = 50.0 + phase_ns + real'(n) * half + jitter();
            if (t > $realtime) #(t - $realtime);
            clk_74a = ~clk_74a;
            n++;
        end
    end

    // ---------------- DUT ----------------
    logic rst = 1'b1;
    logic signed [20:0] in_l = '0, in_r = '0;
    logic run33 = 1'b0;
    wire  mclk, lrck, dac;
    wire  [31:0] dbg_in_count, dbg_out_count;
    wire  [15:0] dbg_ovf_count, dbg_udf_count;
    wire  [4:0]  dbg_level_min;
    wire         dbg_running;

    pocket_audio_out #(.SAMPLE_SRC(`SRC)) dut (
        .clk_core(clk_core), .rst_core(rst),
`ifdef TB_SWAP_INPUTS
        .in_l(in_r), .in_r(in_l),
`else
        .in_l(in_l), .in_r(in_r),
`endif
        .sample_en(1'b0), .run33(run33),
        .clk_74a(clk_74a),
        .audio_mclk(mclk), .audio_lrck(lrck), .audio_dac(dac),
        .dbg_in_count(dbg_in_count), .dbg_out_count(dbg_out_count),
        .dbg_ovf_count(dbg_ovf_count), .dbg_udf_count(dbg_udf_count),
        .dbg_level_min(dbg_level_min), .dbg_running(dbg_running)
    );

    // run33 as DDS_50to33868800 (add 10584, modulus 15625) for SRC=1
    int dds = 0;
    always @(posedge clk_core) begin
        if (dds + 10584 >= 15625) begin dds <= dds + 10584 - 15625; run33 <= 1'b1; end
        else begin dds <= dds + 10584; run33 <= 1'b0; end
    end

    // ---------------- stimulus + reference model ----------------
    localparam real PI = 3.14159265358979323846;
    int k_in = 0;
    int m_prev_l = 0, m_curr_l = 0, m_prev_r = 0, m_curr_r = 0, m_ph = 0;
    int exp_l [$], exp_r [$];

    function automatic int clip(input int v);
        return v > 32767 ? 32767 : (v < -32768 ? -32768 : v);
    endfunction
    function automatic int interp(input int p, input int c, input int ph);
        int up, uc;
        up = p + 32768; uc = c + 32768;
        return (up * 160 + (uc - up) * ph + 80) / 160 - 32768;
    endfunction
    function automatic int stim_l(input int k);   // ramp, strictly changing
        return ((k * 97) % 60000) - 30000;
    endfunction
    function automatic int stim_r(input int k);   // 440 Hz tone
        return $rtoi(20000.0 * $sin(2.0 * PI * 440.0 * real'(k) / 44100.0) + 30000.5) - 30000;
    endfunction

    // dut.smp_stb is only used to learn WHEN the DUT took a sample.
    always @(posedge clk_core) begin
        if (!rst && dut.smp_stb) begin
            m_prev_l = m_curr_l; m_curr_l = clip(int'(in_l));
            m_prev_r = m_curr_r; m_curr_r = clip(int'(in_r));
            while (m_ph < 160) begin
                exp_l.push_back(interp(m_prev_l, m_curr_l, m_ph));
                exp_r.push_back(interp(m_prev_r, m_curr_r, m_ph));
                m_ph += 147;
            end
            m_ph -= 160;
            k_in++;
            in_l <= 21'(stim_l(k_in));
            in_r <= 21'(stim_r(k_in));
        end
    end

    // ---------------- receiver model ----------------
    logic lrck_q = 1'b0;
    bit   locked = 1'b0;
    int   c = 0, slot, n_mclk = 0, n_lrck_edges = 0, lrck_len_err = 0, last_edge_mclk = 0;
    logic [15:0] word;
    logic d1, d2;
    int   stab_err = 0;
    int   dec_l [$], dec_r [$];
    int   n_mclk_win = 0, n_frames_win = 0;
    bit   in_win = 1'b0;

    always @(posedge mclk) begin
        n_mclk++;
        if (in_win) n_mclk_win++;
        if (lrck !== lrck_q) begin
            if (locked && (n_mclk - last_edge_mclk) != 128) lrck_len_err++;
            if (locked && lrck && in_win) n_frames_win++;
            last_edge_mclk = n_mclk;
            n_lrck_edges++;
            if (n_lrck_edges >= 2) locked = 1'b1;   // first full half seen
            lrck_q = lrck;
            c = 1;
            word = '0;
        end else begin
            c++;
        end
        if (locked) begin
            // slot s occupies E(1+4s) .. E(3+4s); sample at E(2+4s)
            if ((c - 1) % 4 == 0) d1 = dac;
            if ((c - 2) % 4 == 0) d2 = dac;
            if ((c - 3) % 4 == 0 && (d1 !== dac || d2 !== dac)) stab_err++;
            if ((c - 2) % 4 == 0) begin
                slot = (c - 2) / 4;
                if (slot >= 1 && slot <= 16) word = {word[14:0], dac};
                if (slot == 16 && n_lrck_edges >= 3) begin
                    if (lrck) dec_r.push_back(int'($signed(word)));
                    else      dec_l.push_back(int'($signed(word)));
                end
            end
        end
    end

    // ---------------- comparison ----------------
    // walk: decoded value must be the next expected one; in udf mode it may
    // repeat the previous decoded value (hold), in ovf mode expected values may
    // be skipped (dropped at the FIFO input).
    int dec [$], expq [$];     // working copies for compare()
    task automatic compare(input string name,
                           output int matched, output int holds, output int skips,
                           output int errs, output int lead, output int jend);
        int i, j, prev;
        matched = 0; holds = 0; skips = 0; errs = 0; lead = 0;
        // leading silence before the FIFO primes: zeros
        i = 0;
        while (i < dec.size() && dec[i] == 0) i++;
        lead = i;
        j = 0;
        while (j < expq.size() && expq[j] == 0) j++;
        prev = 0;
        for (; i < dec.size(); i++) begin
            if (j < expq.size() && dec[i] == expq[j]) begin
                matched++; j++;
            end else if (expect_mode == "udf" && dec[i] == prev) begin
                holds++;
            end else if (expect_mode == "ovf") begin
                int jj;
                jj = j;
                while (jj < expq.size() && jj < j + 8 && dec[i] != expq[jj]) jj++;
                if (jj < expq.size() && dec[i] == expq[jj]) begin
                    skips += jj - j; j = jj + 1; matched++;
                end else begin
                    if (errs < 5) $display("ERROR: %s decoded[%0d]=%0d expected %0d", name, i, dec[i], j < expq.size() ? expq[j] : 99999);
                    errs++;
                end
            end else begin
                if (errs < 5) $display("ERROR: %s decoded[%0d]=%0d expected %0d", name, i, dec[i], j < expq.size() ? expq[j] : 99999);
                errs++;
                if (j < expq.size()) j++;
            end
            prev = dec[i];
        end
        jend = j;
    endtask

    initial begin
        int ml, hl, sl, el, ll, jl, mr, hr, sr, er, lr, jr, errors;
        real win_ms, mclk_hz, fr_hz;
        if (!$value$plusargs("ms=%f", ms)) ms = 60.0;
        if (!$value$plusargs("ppm=%f", ppm)) ppm = 0.0;
        if (!$value$plusargs("jit=%f", jit_ns)) jit_ns = 0.0;
        if (!$value$plusargs("phase=%f", phase_ns)) phase_ns = 3217.0;
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        seed0 = seed;
        if (!$value$plusargs("expect=%s", expect_mode)) expect_mode = "exact";
        jit_ns   = jit_ns / 1000.0;     // plusargs are in ps
        phase_ns = phase_ns / 1000.0;
        in_l = 21'(stim_l(0));
        in_r = 21'(stim_r(0));

        #1000 @(posedge clk_core) rst <= 1'b0;
        #2000000;                              // 2 ms settle (priming, lock)
        in_win = 1'b1;
        win_ms = ms - 2.0 - 1.0;
        #(win_ms * 1.0e6);
        in_win = 1'b0;
        #1000000;

        dec = dec_l; expq = exp_l;
        compare("L", ml, hl, sl, el, ll, jl);
        dec = dec_r; expq = exp_r;
        compare("R", mr, hr, sr, er, lr, jr);
        mclk_hz = real'(n_mclk_win) / (win_ms * 1.0e-3);
        fr_hz   = real'(n_frames_win) / (win_ms * 1.0e-3);
        $display("INFO: SRC=%0d ppm=%0.0f jit=%0.0fps phase=%0.0fps seed=%0d expect=%s",
                 `SRC, ppm, jit_ns * 1000.0, phase_ns * 1000.0, seed0, expect_mode);
        $display("INFO: dut in=%0d out=%0d ovf=%0d udf=%0d level_min=%0d running=%0d",
                 dbg_in_count, dbg_out_count, dbg_ovf_count, dbg_udf_count, dbg_level_min, dbg_running);
        $display("INFO: decoded L=%0d (lead0=%0d matched=%0d holds=%0d skips=%0d) R=%0d (lead0=%0d matched=%0d holds=%0d skips=%0d) expected=%0d consumed L=%0d R=%0d",
                 dec_l.size(), ll, ml, hl, sl, dec_r.size(), lr, mr, hr, sr, exp_l.size(), jl, jr);
        $display("INFO: MCLK %0.1f Hz, frames %0.2f Hz over %0.1f ms, lrck_len_err=%0d stab_err=%0d",
                 mclk_hz, fr_hz, win_ms, lrck_len_err, stab_err);

        errors = el + er + lrck_len_err + stab_err;
        if (ml < 1000 || mr < 1000) begin $display("ERROR: too few matched samples"); errors++; end
        if (mclk_hz < 12.288e6 * (1.0 - 2.0e-4) || mclk_hz > 12.288e6 * (1.0 + 2.0e-4)) begin
            $display("ERROR: MCLK frequency"); errors++;
        end
        if (fr_hz < 48000.0 * (1.0 - 1.0e-3) || fr_hz > 48000.0 * (1.0 + 1.0e-3)) begin
            $display("ERROR: frame rate"); errors++;
        end
        if (expect_mode == "exact") begin
            if (dbg_ovf_count != 0 || dbg_udf_count != 0 || hl + hr + sl + sr != 0) begin
                $display("ERROR: under/overflow in exact mode"); errors++;
            end
            // everything produced is decoded except what is still queued
            // everything produced was decoded in order, except what is still
            // queued (FIFO <= 16, frame register, serializer) at the end
            if (exp_l.size() - jl < 0 || exp_l.size() - jl > 16 + 3 || exp_r.size() - jr > 16 + 3) begin
                $display("ERROR: sample accounting expected=%0d consumed L=%0d R=%0d", exp_l.size(), jl, jr); errors++;
            end
        end else if (expect_mode == "udf") begin
            if (dbg_udf_count == 0 || hl != int'(dbg_udf_count) || hr > hl + 1 || hr < hl - 1 || dbg_ovf_count != 0) begin
                $display("ERROR: underflow accounting holds=%0d udf=%0d", hl, dbg_udf_count); errors++;
            end
        end else begin
            if (dbg_ovf_count == 0 || sl > int'(dbg_ovf_count) || int'(dbg_ovf_count) - sl > 2 ||
                sr > sl + 1 || sr < sl - 1 || dbg_udf_count != 0) begin
                $display("ERROR: overflow accounting skips=%0d ovf=%0d", sl, dbg_ovf_count); errors++;
            end
        end

        if (errors == 0)
            $display("PASS tb_i2s_cdc: SRC=%0d ppm=%0.0f jit=%0.0fps expect=%s frames_L=%0d frames_R=%0d matched=%0d/%0d holds=%0d skips=%0d udf=%0d ovf=%0d stab_err=0 lrck_len_err=0",
                     `SRC, ppm, jit_ns * 1000.0, expect_mode, dec_l.size(), dec_r.size(), ml, mr, hl, sl,
                     dbg_udf_count, dbg_ovf_count);
        else
            $fatal(1, "FAIL tb_i2s_cdc: errors=%0d (L err=%0d R err=%0d stab=%0d lrck=%0d)", errors, el, er, stab_err, lrck_len_err);
        $finish;
    end
endmodule
`default_nettype wire
