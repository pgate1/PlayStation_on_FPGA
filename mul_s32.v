
module mul_s32 (
	a, b, dout, con
);
	input signed [31:0] a, b;
	output signed [63:0] dout;
	input con;

	// 符号付き s32 x s32 = s64 ビット乗算
	assign dout = a * b;

endmodule
