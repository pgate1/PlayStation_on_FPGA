// pocket_audio_out.sv -- PS1 SPU mix (21-bit, 44.1 kHz, core clock) to the
// Analogue Pocket I2S audio port (16-bit stereo, 48 kHz, audio clock).
//
// Roadmap item P05.  See docs/POCKET_AUDIO_OUT.md for the design notes,
// verification commands/results and the integration contract.
//
// Pipeline
//   core clock (clk_core, 50 MHz)
//     sample strobe (external / run33 / 50 MHz phase accumulator, SAMPLE_SRC)
//     -> pocket_audio_sat21   21-bit signed -> 16-bit signed, clip (no wrap)
//     -> pocket_audio_resampler  44.1 -> 48 kHz, exact 147/160 integer phase,
//                                 linear interpolation, round half up
//     -> pocket_audio_afifo   write side (overflow: drop newest, counted)
//   audio clock (clk_74a, 74.25 MHz from APF)
//     -> pocket_audio_afifo   read side (gray-coded pointers, 2-FF syncs)
//     -> prime/run control    (underflow: hold last sample, counted, re-prime)
//     -> pocket_audio_i2s_tx  MCLK 12.288 MHz, SCLK = MCLK/4, LRCK 48 kHz,
//                             APF example-core I2S framing
//
// I2S format (reproduces the Analogue APF template, core_top.v "audio i2s
// silence generator": MCLK by fractional accumulator from clk_74a,
// SCLK = MCLK/4, data and LRCK updated on SCLK falling edges, 32 SCLK per
// channel; the data shifter is the APF example-core one as kept in the MIT
// licensed sound_i2s.sv by Adam Gastineau):
//   - LRCK low = left channel, LRCK high = right channel;
//   - 16-bit two's complement, MSB first, MSB one SCLK after the LRCK edge
//     (standard Philips I2S one-bit delay), followed by 16 dummy bit slots;
//   - DAC/LRCK change one clk_74a cycle after the MCLK rising edge that is
//     the SCLK falling edge, so the receiver's SCLK rising edge (two MCLK
//     periods later) sees stable data.
//
// Clocking: everything on the audio side runs on clk_74a with clock enables;
// MCLK is a register output (as in the template), there are no derived
// internal clocks (the template's ripple clocks audgen_mclk and
// aud_mclk_divider[1] are gone).  The only clock crossing is the FIFO.
//
// Test-only mutation switches (never define them in a build):
//   PA_MUT_WRAP  saturation replaced by truncation (wrap);
//   PA_MUT_SWAP  left/right exchanged in the serializer.
// RATIO_NUM is a parameter only so the testbench can show that a wrong ratio
// fails; it must stay 147.

`timescale 1ns/1ps
`default_nettype none
// Several small modules share this file on purpose (single file to add).
/* verilator lint_off DECLFILENAME */

// ---------------------------------------------------------------------------
// 21-bit signed -> 16-bit signed saturation.
// ---------------------------------------------------------------------------
module pocket_audio_sat21 (
    input  wire  signed [20:0] x,
    output logic signed [15:0] y
);
`ifdef PA_MUT_WRAP
    assign y = x[15:0];
`else
    assign y = (x > 21'sd32767)  ? 16'sh7FFF :
               (x < -21'sd32768) ? 16'sh8000 : x[15:0];
`endif
endmodule

// ---------------------------------------------------------------------------
// 44.1 kHz -> 48 kHz linear-interpolating resampler, exact rational ratio.
//
// Position bookkeeping, in units of 1/160 input sample period:
//   input x[k] sits at 160*(k+1) (x[-1] = 0 after reset, at 0);
//   output n sits at 147*n.
// When x[k] arrives (prev = x[k-1], curr = x[k]) every output with
// 160*k <= 147*n < 160*(k+1) is produced with ph = 147*n - 160*k:
//   y = round_half_up(prev + (curr - prev) * ph / 160)
// computed exactly in offset binary (u = s + 32768, all terms >= 0):
//   N = u_prev*160 + (u_curr - u_prev)*ph + 80   (0 <= N < 2^24)
//   y_u = floor(N / 160) = floor(floor(N / 32) / 5)
//   floor(m / 5) = (m * 419431) >> 21, exact for 0 <= m < 2^19
// After 147 inputs exactly 160 outputs have been produced; ph is an integer,
// so there is no accumulated drift.  Each input yields one or two outputs.
// The FSM needs at most 16 clk cycles per input; a strobe arriving while
// busy is dropped and reported on busy_drop (cannot happen at 44.1 kHz).
// ---------------------------------------------------------------------------
module pocket_audio_resampler #(
    parameter int RATIO_NUM = 147
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               smp_stb,
    input  wire signed [20:0] in_l,
    input  wire signed [20:0] in_r,
    output logic              out_valid,
    output logic signed [15:0] out_l,
    output logic signed [15:0] out_r,
    output logic              busy_drop
);
    localparam logic [8:0] DEN = 9'd160;
    localparam logic [8:0] NUM = RATIO_NUM[8:0];

    localparam logic [2:0] S_IDLE  = 3'd0;
    localparam logic [2:0] S_CHK   = 3'd1;
    localparam logic [2:0] S_MUL   = 3'd2;
    localparam logic [2:0] S_DIV   = 3'd3;
    localparam logic [2:0] S_STORE = 3'd4;

    logic signed [15:0] sat_l, sat_r;
    pocket_audio_sat21 u_sat_l (.x(in_l), .y(sat_l));
    pocket_audio_sat21 u_sat_r (.x(in_r), .y(sat_r));

    // offset binary (s + 32768) <-> two's complement: invert the sign bit
    logic [15:0] prev_l, prev_r, curr_l, curr_r, yl_u;
    logic [2:0]  st;
    logic [8:0]  ph;
    logic        ch;
    logic [18:0] m;          // floor(N / 32)
    logic [15:0] q;

    wire [15:0] up = ch ? prev_r : prev_l;
    wire [15:0] uc = ch ? curr_r : curr_l;
    wire signed [16:0] diff = $signed({1'b0, uc}) - $signed({1'b0, up});
    wire signed [25:0] prod = diff * $signed({1'b0, ph[7:0]});
    wire [25:0] base = ({10'd0, up} << 7) + ({10'd0, up} << 5);
    // modular sum; the true value N is in [0, 2^24) so bits [23:0] are exact
    // (bits [25:24] are zero, bits [4:0] are not needed after the /32)
    /* verilator lint_off UNUSEDSIGNAL */
    wire [25:0] num_w = base + $unsigned(prod) + 26'd80;
    wire [37:0] dprod = {19'd0, m} * 38'd419431;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [15:0] q_w = dprod[36:21];

    always_ff @(posedge clk) begin
        out_valid <= 1'b0;
        busy_drop <= 1'b0;
        if (rst) begin
            st     <= S_IDLE;
            ph     <= 9'd0;
            ch     <= 1'b0;
            prev_l <= 16'h8000; prev_r <= 16'h8000;   // offset-binary zero
            curr_l <= 16'h8000; curr_r <= 16'h8000;
            yl_u   <= 16'h8000;
            m      <= 19'd0;
            q      <= 16'd0;
            out_l  <= 16'sd0;
            out_r  <= 16'sd0;
        end else begin
            if (smp_stb && st != S_IDLE) busy_drop <= 1'b1;
            case (st)
                S_IDLE: if (smp_stb) begin
                    prev_l <= curr_l;
                    prev_r <= curr_r;
                    curr_l <= {~sat_l[15], sat_l[14:0]};
                    curr_r <= {~sat_r[15], sat_r[14:0]};
                    st     <= S_CHK;
                end
                S_CHK: if (ph < DEN) begin
                    ch <= 1'b0;
                    st <= S_MUL;
                end else begin
                    ph <= ph - DEN;
                    st <= S_IDLE;
                end
                S_MUL: begin
                    m   <= num_w[23:5];
                    st  <= S_DIV;
                end
                S_DIV: begin
                    q  <= q_w;
                    st <= S_STORE;
                end
                S_STORE: if (!ch) begin
                    yl_u <= q;
                    ch   <= 1'b1;
                    st   <= S_MUL;
                end else begin
                    out_l     <= $signed({~yl_u[15], yl_u[14:0]});
                    out_r     <= $signed({~q[15], q[14:0]});
                    out_valid <= 1'b1;
                    ph        <= ph + NUM;
                    st        <= S_CHK;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule

// ---------------------------------------------------------------------------
// Dual-clock FIFO, gray-coded pointers with two-flop synchronizers.
// rdata is a registered read of the current head (mem[rbin]); it is valid
// from the first rclk cycle in which rlevel != 0 and one cycle after a pop.
// Write when full and read when empty are ignored (callers count them).
// ---------------------------------------------------------------------------
module pocket_audio_afifo #(
    parameter int W  = 32,
    parameter int AW = 4
) (
    input  wire          wclk,
    input  wire          wrst,
    input  wire          we,
    input  wire [W-1:0]  wdata,
    output logic         wfull,
    output logic [AW:0]  wlevel,
    input  wire          rclk,
    input  wire          rrst,
    input  wire          re,
    output logic [W-1:0] rdata,
    output logic [AW:0]  rlevel
);
    localparam int DEPTH = 1 << AW;

    function automatic logic [AW:0] g2b(input logic [AW:0] g);
        logic [AW:0] b;
        b[AW] = g[AW];
        for (int i = AW - 1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
        return b;
    endfunction

    logic [W-1:0] mem [DEPTH];
    logic [AW:0] wbin, wgray, rgray_w1, rgray_w2;   // write side
    logic [AW:0] rbin, rgray, wgray_r1, wgray_r2, wbin_r;  // read side

    // write side
    wire  [AW:0] rbin_w = g2b(rgray_w2);
    assign wlevel = wbin - rbin_w;
    assign wfull  = wlevel[AW];               // wlevel == DEPTH
    wire  [AW:0] wbin_n = wbin + 1'b1;

    always_ff @(posedge wclk) begin
        if (we && !wfull) mem[wbin[AW-1:0]] <= wdata;
    end

    always_ff @(posedge wclk) begin
        if (wrst) begin
            wbin <= '0; wgray <= '0; rgray_w1 <= '0; rgray_w2 <= '0;
        end else begin
            rgray_w1 <= /* sync */ rgray;
            rgray_w2 <= rgray_w1;
            if (we && !wfull) begin
                wbin  <= wbin_n;
                wgray <= wbin_n ^ (wbin_n >> 1);
            end
        end
    end

    // read side
    assign rlevel = wbin_r - rbin;
    wire  [AW:0] rbin_n = rbin + 1'b1;

    always_ff @(posedge rclk) begin
        rdata <= mem[rbin[AW-1:0]];
    end

    always_ff @(posedge rclk) begin
        if (rrst) begin
            rbin <= '0; rgray <= '0; wgray_r1 <= '0; wgray_r2 <= '0; wbin_r <= '0;
        end else begin
            wgray_r1 <= /* sync */ wgray;
            wgray_r2 <= wgray_r1;
            wbin_r   <= g2b(wgray_r2);
            if (re && rlevel != '0) begin
                rbin  <= rbin_n;
                rgray <= rbin_n ^ (rbin_n >> 1);
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
// APF-template I2S transmitter on clk_74a with clock enables.
// MCLK/SCLK/LRCK and the bit counter are free running (power-up values only),
// as in the template, so a core reset never truncates an I2S frame.
// fetch pulses once per 48 kHz frame (bit slot 16 of the left word); the
// caller must present {frame_l, frame_r} by the next reload, 15 SCLK later.
// ---------------------------------------------------------------------------
module pocket_audio_i2s_tx (
    input  wire        clk_74a,
    input  wire [15:0] frame_l,
    input  wire [15:0] frame_r,
    output logic       fetch,
    output logic       mclk,
    output logic       lrck,
    output logic       dac
);
    // MCLK = 74.25 MHz * 245760 / 742500 / 2 = 12.288 MHz exactly (template)
    localparam logic [21:0] CYCLE_48KHZ = 22'd245760;
    localparam logic [21:0] ACC_WRAP    = 22'd742500;

    // Power-up values only (no reset), like the template's generator.
    /* verilator lint_off PROCASSINIT */
    logic [21:0] acc  = '0;
    logic        mclk_r = 1'b0;
    logic [1:0]  mdiv = '0;            // template aud_mclk_divider; SCLK = mdiv[1]
    logic        step = 1'b0;          // SCLK falling edge, one clk_74a late
    logic [4:0]  cnt  = '0;
    logic        lrck_r = 1'b0;
    logic        dac_r  = 1'b0;
    logic [31:0] shift  = '0;
    logic        fetch_r = 1'b0;
    /* verilator lint_on PROCASSINIT */

    always_ff @(posedge clk_74a) begin
        step    <= 1'b0;
        fetch_r <= 1'b0;
        if (acc >= ACC_WRAP) begin
            acc    <= acc - ACC_WRAP + CYCLE_48KHZ;
            mclk_r <= ~mclk_r;
            if (!mclk_r) begin                 // MCLK rising edge
                mdiv <= mdiv + 2'd1;
                if (mdiv == 2'd3) step <= 1'b1; // SCLK 1 -> 0
            end
        end else begin
            acc <= acc + CYCLE_48KHZ;
        end

        if (step) begin
            dac_r <= shift[31];
            cnt   <= cnt + 5'd1;
            if (cnt == 5'd31) begin
                lrck_r <= ~lrck_r;
                if (!lrck_r) begin
`ifdef PA_MUT_SWAP
                    shift <= {frame_l, frame_r};
`else
                    shift <= {frame_r, frame_l};   // R in LRCK high, then L in LRCK low
`endif
                end
            end else if (cnt < 5'd16) begin
                shift <= {shift[30:0], 1'b0};
            end
            if (cnt == 5'd16 && !lrck_r) fetch_r <= 1'b1;
        end
    end

    assign mclk  = mclk_r;
    assign lrck  = lrck_r;
    assign dac   = dac_r;
    assign fetch = fetch_r;
endmodule

// ---------------------------------------------------------------------------
// Top level.
// ---------------------------------------------------------------------------
module pocket_audio_out #(
    // 0: use sample_en (one clk_core pulse per 44.1 kHz sample)
    // 1: count run33 pulses (33.8688 MHz average), one sample per 768
    // 2: internal phase accumulator: STB_INC/STB_MOD of clk_core
    //    (441/500000 of 50 MHz = 44100 Hz exactly)
    parameter int SAMPLE_SRC = 0,
    parameter int STB_INC    = 441,
    parameter int STB_MOD    = 500000,
    parameter int FIFO_AW    = 4,       // 16 stereo frames
    parameter int PREFILL    = 8,       // frames queued before (re)starting
    parameter int RATIO_NUM  = 147      // test override only
) (
    // core domain
    input  wire               clk_core,
    input  wire               rst_core,     // synchronous to clk_core, active high
    input  wire signed [20:0] in_l,
    input  wire signed [20:0] in_r,
    input  wire               sample_en,
    input  wire               run33,
    // audio domain (APF clk_74a)
    input  wire               clk_74a,
    output logic              audio_mclk,
    output logic              audio_lrck,
    output logic              audio_dac,
    // debug, core domain
    output logic [31:0]       dbg_in_count,     // 44.1 kHz samples accepted
    output logic [31:0]       dbg_out_count,    // 48 kHz samples produced
    output logic [15:0]       dbg_ovf_count,    // samples dropped (FIFO full / busy), saturating
    // debug, audio domain
    output logic [15:0]       dbg_udf_count,    // frames repeated (no fresh sample), saturating
    output logic [FIFO_AW:0]  dbg_level_min,    // lowest FIFO level seen at a fetch while running
    output logic              dbg_running
);
    // ---------------- sample strobe (core domain) ----------------
    logic smp_stb;
    generate
        if (SAMPLE_SRC == 1) begin : g_run33
            logic [9:0] c33;
            always_ff @(posedge clk_core) begin
                smp_stb <= 1'b0;
                if (rst_core) c33 <= 10'd0;
                else if (run33) begin
                    if (c33 == 10'd767) begin c33 <= 10'd0; smp_stb <= 1'b1; end
                    else c33 <= c33 + 10'd1;
                end
            end
        end else if (SAMPLE_SRC == 2) begin : g_acc
            localparam logic [31:0] INC32 = STB_INC;
            localparam logic [31:0] MOD32 = STB_MOD;
            logic [31:0] acc;
            wire  [31:0] acc_n = acc + INC32;
            always_ff @(posedge clk_core) begin
                smp_stb <= 1'b0;
                if (rst_core) acc <= 32'd0;
                else if (acc_n >= MOD32) begin acc <= acc_n - MOD32; smp_stb <= 1'b1; end
                else acc <= acc_n;
            end
        end else begin : g_ext
            assign smp_stb = sample_en;
        end
    endgenerate

    // ---------------- resampler ----------------
    logic              rs_valid, rs_busy_drop;
    logic signed [15:0] rs_l, rs_r;
    pocket_audio_resampler #(.RATIO_NUM(RATIO_NUM)) u_rs (
        .clk(clk_core), .rst(rst_core), .smp_stb(smp_stb),
        .in_l(in_l), .in_r(in_r),
        .out_valid(rs_valid), .out_l(rs_l), .out_r(rs_r), .busy_drop(rs_busy_drop)
    );

    // ---------------- audio-domain reset: async assert, sync release ------
    logic [2:0] rst_aud_s;
    /* verilator lint_off SYNCASYNCNET */
    always_ff @(posedge clk_74a or posedge rst_core) begin
        if (rst_core) rst_aud_s <= 3'b111;
        else          rst_aud_s <= {rst_aud_s[1:0], 1'b0};
    end
    /* verilator lint_on SYNCASYNCNET */
    wire rst_aud = rst_aud_s[2];

    // ---------------- FIFO ----------------
    logic              f_wfull;
    logic [FIFO_AW:0]  f_wlevel, f_rlevel;
    logic [31:0]       f_rdata;
    logic              f_re;
    pocket_audio_afifo #(.W(32), .AW(FIFO_AW)) u_fifo (
        .wclk(clk_core), .wrst(rst_core), .we(rs_valid), .wdata({rs_l, rs_r}),
        .wfull(f_wfull), .wlevel(f_wlevel),
        .rclk(clk_74a), .rrst(rst_aud), .re(f_re), .rdata(f_rdata), .rlevel(f_rlevel)
    );

    // core-domain counters
    always_ff @(posedge clk_core) begin
        if (rst_core) begin
            dbg_in_count  <= 32'd0;
            dbg_out_count <= 32'd0;
            dbg_ovf_count <= 16'd0;
        end else begin
            if (smp_stb)  dbg_in_count  <= dbg_in_count + 32'd1;
            if (rs_valid) dbg_out_count <= dbg_out_count + 32'd1;
            if (((rs_valid && f_wfull) || rs_busy_drop) && dbg_ovf_count != 16'hFFFF)
                dbg_ovf_count <= dbg_ovf_count + 16'd1;
        end
    end

    // ---------------- prime / run control (audio domain) ----------------
    logic        fetch;
    logic [15:0] frame_l, frame_r;
    logic        running, started;
    localparam logic [FIFO_AW:0] PREFILL_L = PREFILL[FIFO_AW:0];

    wire rlevel_ok = running ? (f_rlevel != '0) : (f_rlevel >= PREFILL_L);
    assign f_re = fetch && rlevel_ok;

    always_ff @(posedge clk_74a) begin
        if (rst_aud) begin
            frame_l       <= 16'd0;
            frame_r       <= 16'd0;
            running       <= 1'b0;
            started       <= 1'b0;
            dbg_udf_count <= 16'd0;
            dbg_level_min <= '1;
        end else if (fetch) begin
            if (rlevel_ok) begin
                {frame_l, frame_r} <= f_rdata;       // pop; hold last otherwise
                running <= 1'b1;
                started <= 1'b1;
                if (running && f_rlevel < dbg_level_min) dbg_level_min <= f_rlevel;
            end else begin
                running <= 1'b0;                     // underflow: re-prime
                if (started && dbg_udf_count != 16'hFFFF)
                    dbg_udf_count <= dbg_udf_count + 16'd1;
            end
        end
    end
    assign dbg_running = running;

    // ---------------- serializer ----------------
    pocket_audio_i2s_tx u_tx (
        .clk_74a(clk_74a), .frame_l(frame_l), .frame_r(frame_r),
        .fetch(fetch), .mclk(audio_mclk), .lrck(audio_lrck), .dac(audio_dac)
    );

    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_ok = &{1'b0, sample_en, run33, f_wlevel};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule

/* verilator lint_on DECLFILENAME */
`default_nettype wire
