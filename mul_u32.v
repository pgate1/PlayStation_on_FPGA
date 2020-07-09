
module mul_u32 (
	a, b, dout, con
);
	input [31:0] a, b;
	output [63:0] dout;
	input con;

	// -> •„†‚È‚µ 32x32=64 ƒrƒbƒgæZ
	assign dout = a * b;

endmodule
