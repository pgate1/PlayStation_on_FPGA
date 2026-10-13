// SPDX-License-Identifier: MIT
// Q-L1-16: ram_320x240x15_dp (Pocket/rtl/ram_320x240x15_dp.sv) with the same ports and
// behaviour, but inferred with max_depth 2048 so Quartus packs it as 2K x 5 M10K slices:
// 38 x 3 = 114 blocks instead of the 144 of the default packing. Two view buffers then
// fit next to the core (2 x 114 + 26 of 308 blocks); the cost is a wider read mux.
// Registered read: dout shows the word addressed in the previous cycle with rd_en.
`default_nettype none

module ram_320x240x15_dp_2k5 (
    input  wire         clk,
    input  wire         wr_en,
    input  wire [16:0]  wr_adrs,
    input  wire [14:0]  wr_data,
    input  wire         rd_en,
    input  wire [16:0]  rd_adrs,
    output logic [14:0] dout
);
    localparam integer DEPTH = 320 * 240;

    (* ramstyle = "M10K", max_depth = 2048 *) logic [14:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_adrs] <= wr_data;
        if (rd_en)
            dout <= mem[rd_adrs];
    end
endmodule

`default_nettype wire
