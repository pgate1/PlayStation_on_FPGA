
module mul_u9 (
	a, b, dout, con
);
	input [8:0] a, b;
	output [17:0] dout;
	input con;

	// -> •„†‚È‚µ 9x9=18 ƒrƒbƒgæZ
	assign dout = a * b;

endmodule
