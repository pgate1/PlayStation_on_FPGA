
module mul_u8 (
	a, b, dout, con
);
	input [7:0] a, b;
	output [15:0] dout;
	input con;

	// -> •„†‚È‚µ 8x8=16 ƒrƒbƒgæZ
	assign dout = a * b;

endmodule
