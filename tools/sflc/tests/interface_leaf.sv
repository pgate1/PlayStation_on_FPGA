// A combinational Verilog leaf: interface declarations must not add clocks.
module leaf(input wire con, input wire [7:0] x, output wire [7:0] q);
  assign q = con ? (x ^ 8'h5a) : 8'hc3;
endmodule
