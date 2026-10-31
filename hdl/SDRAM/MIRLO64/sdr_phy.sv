// Derived from LiteX (BSD 2-Clause, (c) Enjoy-Digital; see NOTICE).
// The Pocket's SDR SDRAM PHY (AS4C32M16: 16-bit, CL 3, BL 2), half rate: the
// controller runs on sys and hands two phases per sys cycle; the pads run on
// sys2x. Register for register, the timing is what the board was tuned to:
//
//   - every controller output is registered once in sys (the DFI stage)
//     before it crosses into sys2x (the crossing has one sys2x period);
//   - phase_sel picks phase 0 on the first sys2x cycle of a sys cycle, 1 on
//     the second; commands and write data go out through one full-rate path;
//   - a write drives two beats (phase 0's data, then phase 1's) from phase 0's
//     wrdata_en; DM is registered with them;
//   - reads: the DQ input registered twice in sys2x, the first beat once more,
//     then both into sys: {second beat, first beat}, valid read_latency = 5
//     sys cycles after rddata_en (the chip model
//     passes at offset 0 only).
//
// The SDRAM clock is sys2x_90deg through a DDR output (as the board needs it).
`default_nettype none

module sdr_phy (
    input  wire         clk,            // sys
    input  wire         rst,
    input  wire         clk2x,          // sys2x
    input  wire         rst2x,          // sys2x's reset (registered in sys2x)
    input  wire         clk2x_90,       // the SDRAM clock's source
    // DFI, two phases (sys)
    input  wire  [1:0]  ras_n, cas_n, we_n,
    input  wire  [25:0] addr,           // {p1, p0} x 13
    input  wire  [3:0]  ba,             // {p1, p0} x 2
    input  wire         cke,
    input  wire         wrdata_en,      // phase 0's: two beats
    input  wire  [31:0] wrdata,         // {p1, p0}
    input  wire  [3:0]  wrdata_mask,    // {p1, p0} x 2: 1 = byte not written
    input  wire         rddata_en,      // phase 0's
    output logic [31:0] rddata,         // {second beat, first beat}
    output logic        rddata_valid,
    // pads
    output wire  [12:0] sdram_a,
    output wire  [1:0]  sdram_ba,
    output logic        sdram_ras_n, sdram_cas_n, sdram_we_n, sdram_cke,
    output logic [1:0]  sdram_dm,
    inout  wire  [15:0] sdram_dq,
    output wire         sdram_clock
);

// ---- DFI register stage (sys)
logic [1:0]  r_ras_n = 2'b11, r_cas_n = 2'b11, r_we_n = 2'b11;
logic [25:0] r_addr;
logic [3:0]  r_ba;
logic        r_cke, r_wrdata_en, r_rddata_en;
logic [31:0] r_wrdata;
logic [3:0]  r_wrdata_mask;
always_ff @(posedge clk) begin
    if (rst) begin
        r_ras_n <= 2'b11; r_cas_n <= 2'b11; r_we_n <= 2'b11; r_addr <= '0; r_ba <= '0; r_cke <= 0;
        r_wrdata_en <= 0; r_rddata_en <= 0; r_wrdata <= '0; r_wrdata_mask <= '0;
    end else begin
        r_ras_n <= ras_n; r_cas_n <= cas_n; r_we_n <= we_n; r_addr <= addr; r_ba <= ba; r_cke <= cke;
        r_wrdata_en <= wrdata_en; r_rddata_en <= rddata_en; r_wrdata <= wrdata; r_wrdata_mask <= wrdata_mask;
    end
end

// ---- phase select (sys2x): 0 on the first sys2x cycle of each sys cycle
logic phase_sel, phase_sys2x, phase_sys;
always_ff @(posedge clk) phase_sys <= rst ? 1'b0 : phase_sys2x;
always_ff @(posedge clk2x)
    if (rst2x) begin phase_sel <= 0; phase_sys2x <= 0; end
    else begin
        phase_sys2x <= ~phase_sel;
        phase_sel <= ~phase_sel & (phase_sys2x ^ phase_sys);
    end

// ---- the full-rate path (sys2x)
wire        f_ras_n = phase_sel ? r_ras_n[1] : r_ras_n[0];
wire        f_cas_n = phase_sel ? r_cas_n[1] : r_cas_n[0];
wire        f_we_n  = phase_sel ? r_we_n[1]  : r_we_n[0];
wire [12:0] f_addr  = phase_sel ? r_addr[25:13] : r_addr[12:0];
wire [1:0]  f_ba    = phase_sel ? r_ba[3:2] : r_ba[1:0];
wire [15:0] f_wrdata = phase_sel ? r_wrdata[31:16] : r_wrdata[15:0];
wire [1:0]  f_mask  = phase_sel ? r_wrdata_mask[3:2] : r_wrdata_mask[1:0];
wire        f_rden  = phase_sel ? 1'b0 : r_rddata_en;         // (phase 1's rddata_en: never set)
logic       wr_en_d;
wire        f_wren  = (r_wrdata_en & !phase_sel) | wr_en_d;

// The address and the bank: registered on their own, with no reset (the
// commands are NOPs while in reset: what they hold then is no matter) and no
// synchronous control signals, so the Fitter can put them in the pads' output
// registers (FAST_OUTPUT_REGISTER) as it does the commands, DQ and DM. With the
// reset, synthesis folded the phase mux into the register's synchronous load
// beside its clear, an I/O register cannot have both (Warning 176279), and the
// address left from the fabric 8 to 11 ns from its clock, unconstrained, on
// the SDRAM clock's edge: a few bits sampled a cycle late, which bits a matter
// of placement (a2bbe00's builds: the program read back wrong, the screen black).
(* altera_attribute = "-name ALLOW_SYNCH_CTRL_USAGE OFF" *) logic [12:0] a_q;
(* altera_attribute = "-name ALLOW_SYNCH_CTRL_USAGE OFF" *) logic [1:0]  ba_q;
always_ff @(posedge clk2x) begin a_q <= f_addr; ba_q <= f_ba; end
assign sdram_a = a_q; assign sdram_ba = ba_q;
logic [15:0] out_reg, in1, in2, f_rddata, rddata_d;
logic        oe_reg, f_rdvalid;
logic [4:0]  rden_sr;
always_ff @(posedge clk2x) begin
    if (rst2x) begin
        sdram_ras_n <= 1; sdram_cas_n <= 1; sdram_we_n <= 1; sdram_cke <= 0;
        sdram_dm <= '0; out_reg <= '0; oe_reg <= 0; in2 <= '0; f_rddata <= '0; rden_sr <= '0; f_rdvalid <= 0;
        wr_en_d <= 0; rddata_d <= '0;
    end else begin
        sdram_ras_n <= f_ras_n; sdram_cas_n <= f_cas_n; sdram_we_n <= f_we_n; sdram_cke <= r_cke;
        out_reg <= f_wrdata; oe_reg <= f_wren;
        sdram_dm <= {2{f_wren}} & f_mask;
        in2 <= in1; f_rddata <= in2;
        rden_sr <= {rden_sr[3:0], f_rden};
        f_rdvalid <= rden_sr[4];
        wr_en_d <= r_wrdata_en & !phase_sel;
        rddata_d <= f_rddata;
    end
end
assign sdram_dq = oe_reg ? out_reg : 16'bz;
assign in1 = sdram_dq;

// ---- reads back into sys
always_ff @(posedge clk)
    if (rst) begin rddata <= '0; rddata_valid <= 0; end
    else begin
        rddata <= {f_rddata, rddata_d};
        rddata_valid <= f_rdvalid;
    end

// ---- the SDRAM clock
`ifdef VERILATOR
assign sdram_clock = clk2x_90;
`else
ALTDDIO_OUT #(.WIDTH(1)) clk_out (.datain_h(1'b1), .datain_l(1'b0), .outclock(clk2x_90), .dataout(sdram_clock));
`endif

endmodule
`default_nettype wire
