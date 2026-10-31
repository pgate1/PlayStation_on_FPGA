// SPDX-License-Identifier: MIT
// Pocket async SRAM (128K x 16 = 256 KiB, 17-bit word address, matches core_top.v sram_a[16:0]) controller.
// Replacement for the private sram_ctrl.h used by Pocket/core.sflp (sram.read / sram.write / sram.ack / sram.dout).
// Assumed, because the generated interface is not in the repository:
//   - one command at a time; rd_req/wr_req are ignored while busy; rd_req wins if both are high;
//   - ack is a one-clock completion pulse; for reads, dout is valid from that cycle on;
//   - pin polarity follows Pocket/core_top.v: OEn/WEn/UBn/LBn active low, DEn low drives Din onto the bus.
// Timing (one clock per phase, read data sampled 2 clocks after the address is driven):
//   read : addr+OEn at T, sample Dout at T+2, ack at T+3.
//   write: addr+Din+DEn at T, WEn low for one clock (T+1..T+2), DEn released at T+3, ack at T+3.
// The clock period must exceed the SRAM read access time and the write pulse width. Confirm
// against the device datasheet and the actual SRAM clock before relying on it.
`timescale 1ns/1ps
`default_nettype none

module sram_ctrl (
    input  wire         clk,
    input  wire         rst,

    input  wire         rd_req,
    input  wire         wr_req,
    input  wire [16:0]  adrs,
    input  wire [15:0]  wdata,
    output logic        ack,
    output logic [15:0] dout,
    output logic        busy,

    output logic        OEn,
    output logic        WEn,
    output logic        UBn,
    output logic        LBn,
    output logic        DEn,
    output logic [16:0] ADDR,
    output logic [15:0] Din,
    input  wire  [15:0] Dout
);
    typedef enum logic [2:0] {
        S_IDLE, S_RD_WAIT, S_RD_CAP, S_WR_SETUP, S_WR_STROBE, S_WR_HOLD
    } state_t;

    state_t st;

    assign busy = (st != S_IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            st   <= S_IDLE;
            OEn  <= 1'b1;
            WEn  <= 1'b1;
            UBn  <= 1'b0;
            LBn  <= 1'b0;
            DEn  <= 1'b1;
            ack  <= 1'b0;
            ADDR <= '0;
            Din  <= '0;
            dout <= '0;
        end else begin
            ack <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (rd_req) begin
                        ADDR <= adrs;
                        OEn  <= 1'b0;
                        st   <= S_RD_WAIT;
                    end else if (wr_req) begin
                        ADDR <= adrs;
                        Din  <= wdata;
                        DEn  <= 1'b0;
                        st   <= S_WR_SETUP;
                    end
                end
                S_RD_WAIT: st <= S_RD_CAP;
                S_RD_CAP: begin
                    dout <= Dout;
                    OEn  <= 1'b1;
                    ack  <= 1'b1;
                    st   <= S_IDLE;
                end
                S_WR_SETUP: begin
                    WEn <= 1'b0;
                    st  <= S_WR_STROBE;
                end
                S_WR_STROBE: begin
                    WEn <= 1'b1;
                    st  <= S_WR_HOLD;
                end
                S_WR_HOLD: begin
                    DEn <= 1'b1;
                    ack <= 1'b1;
                    st  <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
