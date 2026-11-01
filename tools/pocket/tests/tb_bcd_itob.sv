`timescale 1ns/1ps
module tb_bcd_itob;
    reg [7:0] bin;
    wire [7:0] bcd;
    bcd_itob dut(
        .bin(bin),
        .bcd(bcd),
        .con(1'b0)
    );

    integer i;
    reg [3:0] exp_tens;
    reg [3:0] exp_units;
    reg [7:0] exp_bcd;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            bin = i[7:0];
            exp_tens = (i / 10);
            exp_units = (i % 10);
            exp_bcd = {exp_tens, exp_units};
            #1;
            if (bcd !== exp_bcd) begin
                $fatal(1, "Mismatch at bin=%0d: expected bcd=%h, got %h", i, exp_bcd, bcd);
            end
        end
        $display("PASS tb_bcd_itob all 256 inputs verified");
        $finish;
    end
endmodule
