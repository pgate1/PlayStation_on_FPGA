
module mul_u16 (
	a, b, dout, con
);
	input [15:0] a, b;
	output [31:0] dout;
	input con;

	// -> •„†‚È‚µ 16x16=32 ƒrƒbƒgæZ
	assign dout = a * b;

endmodule
