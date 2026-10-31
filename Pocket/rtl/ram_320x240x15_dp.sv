// SPDX-License-Identifier: MIT
// Replacement for the private sfl-generated ram_320x240x15_dp (view_ram_ctrl.sflp:4,19).
// Port names are assumed: the generated .h is not in the repository.
// Registered read: dout shows the word addressed in the previous cycle with rd_en.
// Same-address read/write in one cycle returns the OLD contents (read-before-write).
// Depth 320*240 = 76800 words of 15 bits; the 17-bit address is used as-is.
`default_nettype none

module ram_320x240x15_dp (
    input  wire         clk,
    input  wire         wr_en,
    input  wire [16:0]  wr_adrs,
    input  wire [14:0]  wr_data,
    input  wire         rd_en,
    input  wire [16:0]  rd_adrs,
    output logic [14:0] dout
);
    localparam integer DEPTH = 320 * 240;

    logic [14:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_adrs] <= wr_data;
        if (rd_en)
            dout <= mem[rd_adrs];
    end
endmodule

`default_nettype wire
