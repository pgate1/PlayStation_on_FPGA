
module mul_s16 (
	a, b, dout, con
);
	input signed [15:0] a, b;
	output signed [31:0] dout;
	input con;

	// -> 符号付き 16x16=32 ビット乗算
	assign dout = a * b;

endmodule
