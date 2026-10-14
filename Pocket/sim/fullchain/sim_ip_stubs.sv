// SPDX-License-Identifier: MIT
// Simulation stand-ins for the two Intel IP blocks core_top.v instantiates
// (Q-L1-16 full-chain boot simulation, Pocket/sim/fullchain/tb_pocket_boot.sv).
//
// main_pll_0002: the prepared PLL (tools/pocket/prepare_ps1_project.py PLL_40 +
//   video-60hz + --sdram-phase): outclk_0 core clock, outclk_1 = 2 x core
//   (SDRAM controller/pad clock), outclk_2 = outclk_1 shifted by SDRAM_PHASE
//   degrees (the SDRAM clock source), outclk_3/4 video clock and its 90-degree
//   copy. outclk_0 and outclk_1 toggle in one process so the sys and sys2x
//   flops of sdr_phy see one edge (no delta race), as in
//   Pocket/tb/tb_sdram128_burstn_pins.sv. `locked` rises LOCK_NS after start.
// mf_datatable: the APF data table (256 x 32 dual-port altsyncram).
`timescale 1ns/1ps
`default_nettype none

`ifndef SIM_CORE_PERIOD_NS
`define SIM_CORE_PERIOD_NS 25.0
`endif
`ifndef SIM_SDRAM_PHASE
`define SIM_SDRAM_PHASE 270
`endif
module main_pll_0002 #(
    parameter real CORE_PERIOD_NS = `SIM_CORE_PERIOD_NS,   // 40 MHz (core-40mhz); set by run_pocket_sim.py from the manifest
    parameter int  SDRAM_PHASE    = `SIM_SDRAM_PHASE,      // degrees of outclk_1
    parameter real LOCK_NS        = 2000.0
) (
    input  wire refclk,
    input  wire rst,
    output reg  outclk_0,
    output reg  outclk_1,
    output reg  outclk_2,
    output reg  outclk_3,
    output reg  outclk_4,
    output reg  locked
);
    localparam real Q = CORE_PERIOD_NS / 4.0;            // quarter core period = half of outclk_1
    localparam real PH = (CORE_PERIOD_NS / 2.0) * SDRAM_PHASE / 360.0;
    initial begin
        outclk_0 = 0; outclk_1 = 0; outclk_2 = 0; outclk_3 = 0; outclk_4 = 0; locked = 0;
        forever begin
            #(Q) outclk_1 = 1; outclk_0 = ~outclk_0; outclk_3 = outclk_0;
            #(Q) outclk_1 = 0;
        end
    end
    // one process per edge: a delay longer than half the period would otherwise miss edges
    always @(posedge outclk_1) begin #(PH) outclk_2 = 1; end
    always @(negedge outclk_1) begin #(PH) outclk_2 = 0; end
    always @(posedge outclk_3) begin #(CORE_PERIOD_NS / 4.0) outclk_4 = 1; end
    always @(negedge outclk_3) begin #(CORE_PERIOD_NS / 4.0) outclk_4 = 0; end
    initial begin
        #(LOCK_NS) locked = 1;
    end
endmodule

module mf_datatable (
    input  wire [7:0]  address_a,
    input  wire [7:0]  address_b,
    input  wire        clock_a,
    input  wire        clock_b,
    input  wire [31:0] data_a,
    input  wire [31:0] data_b,
    input  wire        wren_a,
    input  wire        wren_b,
    output reg  [31:0] q_a,
    output reg  [31:0] q_b
);
    reg [31:0] mem [0:255];
    integer i;
    initial for (i = 0; i < 256; i = i + 1) mem[i] = 0;
    always @(posedge clock_a) begin
        if (wren_a) mem[address_a] <= data_a;
        q_a <= mem[address_a];
    end
    always @(posedge clock_b) begin
        if (wren_b) mem[address_b] <= data_b;
        q_b <= mem[address_b];
    end
endmodule

`default_nettype wire
