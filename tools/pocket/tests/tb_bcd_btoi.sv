`timescale 1ns/1ps
module tb_bcd_btoi;
    reg [7:0] bcd;
    wire [7:0] bin;
    bcd_btoi dut(
        .bcd(bcd),
        .bin(bin),
        .con(1'b0)
    );

    integer i;
    reg [3:0] tens;
    reg [3:0] units;
    reg [7:0] exp_bin;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            bcd = i[7:0];
            tens = bcd[7:4];
            units = bcd[3:0];
            exp_bin = (tens * 8'd10) + units;
            #1;
            if (bin !== exp_bin) begin
                $fatal(1, "Mismatch at bcd=%h: expected bin=%0d, got %0d", bcd, exp_bin, bin);
            end
        end
        $display("PASS tb_bcd_btoi all 256 inputs verified");
        $finish;
    end
endmodule
