// SPDX-License-Identifier: MIT
// Stand-in for the author's private `sdram128_burstn_ctrl_100` (instantiated by
// Pocket/core_top.v), built on the MIRLO64 SDR controller and PHY
// (hdl/SDRAM/MIRLO64/sdr_ctrl.sv, Apache-2.0; sdr_phy.sv, BSD-2-Clause).
//
// Q-L1-14 milestone 1: resource-realistic and simulated against a behavioural
// word controller (Pocket/tb/tb_sdram128_burstn_adapter.sv). NOT validated on
// hardware, NOT timing-closed, and the original controller's behaviour is not
// known. Every interface assumption is listed here and in docs/POCKET_PS1_BUILD.md.
//
// Interface as used by Pocket/core.sflp and Pocket/core_top.v (inferred):
//   adrs<25>   16-bit halfword address in the 64 MiB device (WRAM 0x000000,
//              VRAM 0x100000, BIOS 0x800000 halfwords; core.sflp comments).
//   burst<4>   number of halfwords, 1..8 (core: byte 16/12/8/4 -> 8/6/4/2).
//              ASSUMPTION: 0 and 9..15 are treated as 8.
//   din<128>   first halfword in bits 15:0, then ascending.
//   enable<16> one bit per byte of din (writes). Bytes beyond 2*burst ignored.
//   dout<128>  read data packed like din. Bytes beyond the burst are not
//              cleared (ASSUMPTION; core.sflp only uses requested lanes). Held
//              until the next read completes.
//   read/write one-clock strobes. If both are high, write wins (they are only
//              both high when core_top's OR-combined masters collide; upstream
//              hazard, not resolved here).
//   ack        ASSUMPTION (ack convention unresolved upstream,
//              docs/POCKET_START_HERE.md): a level "idle/done" signal. core.sflp
//              registers it once (sdram_ack := sdram_ack_100), issues a new
//              command only while the registered copy is 1 (wram_clear,
//              alt{^sdram_ack : ;}) and treats a 1 as completion of the
//              previous command (psx.wram_ack(), gpu acks). So the registered
//              copy must already be 0 in the cycle after a strobe. Here:
//                ack = init done & idle & ~(read | write)   (combinational),
//              it rises in the cycle after a read's data is in dout or a
//              write's last word is accepted by sdr_ctrl (which executes in
//              order, so later reads observe it).
//   manual_refresh, refresh_go: tied 0 upstream; ignored (sdr_ctrl refreshes).
// Commands arriving while not idle are dropped and counted in `dropped`
// (debug). The core never does that if the ack convention above holds; the APF
// loader path (word_wr_r) is not ack-gated upstream.
//
// Clocks (ASSUMPTION, changed from the author's single 100 MHz controller
// domain): the command side and sdr_ctrl run on clk (= core clk_50); sdr_phy
// uses clk2x (2 x clk, phase aligned, 100 MHz) and clk2x_90 (the SDRAM pin
// clock source). sdr_ctrl was tuned for 62.832 MHz; only T_REFI is rescaled
// (7.8 us / 20 ns = 390 -> 380). The other counts are conservative at 50 MHz.
`default_nettype none

module sdram128_burstn_wordside (
    input  wire          clk,
    input  wire          rst,
    // author-style command side
    input  wire          write,
    input  wire  [24:0]  adrs,
    input  wire  [127:0] din,
    input  wire  [15:0]  enable,
    input  wire  [3:0]   burst,
    input  wire          read,
    output logic [127:0] dout,
    output logic         ack,
    output logic         ready,        // ack without the ~strobe term (for a second master's arbiter)
    output logic [15:0]  dropped,      // saturating count of strobes while busy
    output logic         stray,        // sticky: read data without a request
    // MIRLO sdr_ctrl request/response side
    input  wire          ctrl_ready,   // init sequence done
    output logic         req_valid,
    output logic         req_we,
    output logic [23:0]  req_addr,
    output logic [31:0]  req_wdata,
    output logic [3:0]   req_be,
    output logic [2:0]   req_tag,
    input  wire          req_ready,
    input  wire          rd_valid,
    input  wire  [31:0]  rd_data,
    input  wire  [2:0]   rd_tag
);
    typedef enum logic [1:0] { S_IDLE, S_ISSUE, S_WAIT } st_t;
    st_t st;

    logic         we, off;
    logic [23:0]  base;
    logic [2:0]   nwords, widx, rcnt;
    logic [159:0] wbuf;
    logic [19:0]  wmask;
    logic [31:0]  rbuf [5];

    wire strobe = read | write;
    assign ready = ctrl_ready & (st == S_IDLE);
    assign ack = ready & ~strobe;

    // request decode (combinational, used on acceptance)
    wire [3:0]   len    = (burst == 4'd0 || burst > 4'd8) ? 4'd8 : burst;
    wire [15:0]  lenmask = 16'hFFFF >> (5'd16 - {len, 1'b0});
    wire [15:0]  be16   = enable & lenmask;
    wire [4:0]   span   = {4'd0, adrs[0]} + {1'b0, len} + 5'd1;

    assign req_valid = (st == S_ISSUE);
    assign req_we    = we;
    assign req_addr  = base + {21'd0, widx};
    assign req_tag   = widx;
    assign req_wdata = wbuf[widx * 32 +: 32];
    assign req_be    = wmask[widx * 4 +: 4];

    // read gather: the word arriving this cycle merged in
    logic [159:0] gathered;
    always_comb begin
        for (int i = 0; i < 5; i++)
            gathered[i * 32 +: 32] = (rd_valid && rd_tag == 3'(i)) ? rd_data : rbuf[i];
    end
    wire last_issue = req_ready && (widx == nwords - 3'd1);
    wire last_read  = rd_valid && (rcnt == nwords - 3'd1);

    always_ff @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; widx <= '0; rcnt <= '0; we <= 1'b0; off <= 1'b0;
            nwords <= 3'd1; base <= '0; dropped <= '0; stray <= 1'b0;
        end else begin
            if (strobe && st != S_IDLE && dropped != 16'hFFFF) dropped <= dropped + 16'd1;
            if (rd_valid && (st == S_IDLE || we)) stray <= 1'b1;
            if (rd_valid) rbuf[rd_tag] <= rd_data;
            case (st)
            S_IDLE: if (strobe && ctrl_ready) begin
                we     <= write;
                off    <= adrs[0];
                base   <= adrs[24:1];
                nwords <= span[3:1];
                widx   <= '0;
                rcnt   <= '0;
                wbuf   <= {32'd0, din} << (adrs[0] ? 16 : 0);
                wmask  <= {4'd0, be16} << (adrs[0] ? 2 : 0);
                st     <= S_ISSUE;
            end
            S_ISSUE: begin
                if (req_ready) widx <= widx + 3'd1;
                if (!we && rd_valid) rcnt <= rcnt + 3'd1;
                if (last_issue) begin
                    if (we) st <= S_IDLE;
                    else    st <= S_WAIT;
                end
                // a read cannot complete before its last word is issued (RL >= 1)
            end
            S_WAIT: begin
                if (rd_valid) rcnt <= rcnt + 3'd1;
                if (last_read) begin
                    dout <= off ? gathered[143:16] : gathered[127:0];
                    st   <= S_IDLE;
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule

module sdram128_burstn_adapter #(
    parameter int T_INIT = 12600,
    parameter int T_REFI = 380
) (
    input  wire          clk,          // core clock (clk_50): command side + sdr_ctrl
    input  wire          clk2x,        // 2 x clk, phase aligned (sdr_phy pad side)
    input  wire          clk2x_90,     // SDRAM clock source
    input  wire          p_reset,      // asynchronous, active high (PLL not locked)
    // author interface (see header)
    input  wire          write,
    input  wire  [24:0]  adrs,
    input  wire  [127:0] din,
    input  wire  [15:0]  enable,
    input  wire  [3:0]   burst,
    input  wire          read,
    output logic [127:0] dout,
    input  wire          manual_refresh,
    input  wire          refresh_go,
    output logic         ack,
    output logic         ready,        // ack without the ~strobe term: a second master may strobe when
                                       // ready and the first one does not (Q-L1-16 loader FIFO)
    output logic [15:0]  dropped,
    output logic         stray,
    // SDRAM pads
    output wire  [12:0]  sdram_a,
    output wire  [1:0]   sdram_ba,
    output logic         sdram_ras_n,
    output logic         sdram_cas_n,
    output logic         sdram_we_n,
    output logic         sdram_cke,
    output logic [1:0]   sdram_dm,
    inout  wire  [15:0]  sdram_dq,
    output wire          sdram_clock
);
    // reset synchronizers: asynchronous assert, synchronous release
    logic [1:0] rs, rs2;
    always_ff @(posedge clk or posedge p_reset)
        if (p_reset) rs <= 2'b11; else rs <= {rs[0], 1'b0};
    always_ff @(posedge clk2x or posedge p_reset)
        if (p_reset) rs2 <= 2'b11; else rs2 <= {rs2[0], 1'b0};
    wire rst = rs[1], rst2x = rs2[1];

    logic        ctrl_ready, req_valid, req_we, req_ready, rd_valid, rd_next;
    logic [23:0] req_addr;
    logic [31:0] req_wdata, rd_data;
    logic [3:0]  req_be;
    logic [2:0]  req_tag, rd_tag, rd_next_tag;

    sdram128_burstn_wordside u_word (
        .clk, .rst, .write, .adrs, .din, .enable, .burst, .read, .dout, .ack, .ready,
        .dropped, .stray, .ctrl_ready, .req_valid, .req_we, .req_addr, .req_wdata,
        .req_be, .req_tag, .req_ready, .rd_valid, .rd_data, .rd_tag);

    logic [1:0]  dfi_ras_n, dfi_cas_n, dfi_we_n;
    logic [25:0] dfi_addr;
    logic [3:0]  dfi_ba, dfi_wrdata_mask;
    logic        dfi_cke, dfi_wrdata_en, dfi_rddata_en, dfi_rddata_valid;
    logic [31:0] dfi_wrdata, dfi_rddata;

    sdr_ctrl #(.T_INIT(T_INIT), .T_REFI(T_REFI)) u_ctrl (
        .clk, .rst, .ready(ctrl_ready),
        .req_valid, .req_we, .req_addr, .req_wdata, .req_be, .req_tag, .req_ready,
        .la_valid(1'b0), .la_addr(24'd0),
        .rd_valid, .rd_data, .rd_tag, .rd_next, .rd_next_tag,
        .dfi_ras_n, .dfi_cas_n, .dfi_we_n, .dfi_addr, .dfi_ba, .dfi_cke,
        .dfi_wrdata_en, .dfi_wrdata, .dfi_wrdata_mask, .dfi_rddata_en,
        .dfi_rddata, .dfi_rddata_valid);

    sdr_phy u_phy (
        .clk, .rst, .clk2x, .rst2x, .clk2x_90,
        .ras_n(dfi_ras_n), .cas_n(dfi_cas_n), .we_n(dfi_we_n), .addr(dfi_addr),
        .ba(dfi_ba), .cke(dfi_cke), .wrdata_en(dfi_wrdata_en), .wrdata(dfi_wrdata),
        .wrdata_mask(dfi_wrdata_mask), .rddata_en(dfi_rddata_en),
        .rddata(dfi_rddata), .rddata_valid(dfi_rddata_valid),
        .sdram_a, .sdram_ba, .sdram_ras_n, .sdram_cas_n, .sdram_we_n, .sdram_cke,
        .sdram_dm, .sdram_dq, .sdram_clock);
endmodule

`default_nettype wire
