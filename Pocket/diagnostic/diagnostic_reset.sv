`timescale 1ns/1ps
// Asynchronously assert reset on host reset or PLL loss; release after two
// consecutive pixel-clock edges with both sources inactive.
module diagnostic_reset (
    input  wire clk_pixel,
    input  wire host_reset_n,
    input  wire pll_locked,
    output wire pixel_reset_n
);
    reg [1:0] release_sync;
    wire async_reset_n = host_reset_n & pll_locked;

    always @(posedge clk_pixel or negedge async_reset_n) begin
        if (!async_reset_n)
            release_sync <= 2'b00;
        else
            release_sync <= {release_sync[0], 1'b1};
    end

    assign pixel_reset_n = release_sync[1];
endmodule
