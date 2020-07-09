
module mul_s16s8 (
	a, b, dout, con
);
	input signed [15:0] a;
	input signed [7:0] b;
	output signed [23:0] dout;
	input con;

	// -> 符号付き s16 x s8 = 24 ビット乗算
	assign dout = a * b;

endmodule
