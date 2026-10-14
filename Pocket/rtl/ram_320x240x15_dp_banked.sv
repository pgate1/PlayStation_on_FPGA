// SPDX-License-Identifier: MIT
// Q-L1-16: ram_320x240x15_dp (Pocket/rtl/ram_320x240x15_dp.sv) with the same ports and
// behaviour, built from 38 inferred 2048 x 15 banks (3 M10K each, 114 in total) so that
// Analysis & Synthesis budgets the exact block count (two view buffers, 2 x 114 + 26 of
// 308). Alternative to ram_320x240x15_dp_2k5.sv (explicit altsyncram), which showed a
// black picture on hardware (r26, r19b).
// Registered read: dout shows the word addressed in the previous cycle with rd_en.
`default_nettype none

module ram_320x240x15_dp_banked (
    input  wire         clk,
    input  wire         wr_en,
    input  wire [16:0]  wr_adrs,
    input  wire [14:0]  wr_data,
    input  wire         rd_en,
    input  wire [16:0]  rd_adrs,
    output logic [14:0] dout
);
    localparam integer BANKS = 38;           // 38 x 2048 = 77824 >= 320 * 240

    logic [14:0] q [BANKS];
    logic [5:0]  rd_bank;

    genvar b;
    generate
        for (b = 0; b < BANKS; b = b + 1) begin : g_bank
            logic [14:0] mem [0:2047];
            always_ff @(posedge clk) begin
                if (wr_en && wr_adrs[16:11] == b)
                    mem[wr_adrs[10:0]] <= wr_data;
                if (rd_en)
                    q[b] <= mem[rd_adrs[10:0]];
            end
        end
    endgenerate

    always_ff @(posedge clk)
        if (rd_en) rd_bank <= rd_adrs[16:11];

    assign dout = (rd_bank < BANKS) ? q[rd_bank] : 15'd0;
endmodule

`default_nettype wire
