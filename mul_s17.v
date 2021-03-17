
module mul_s17 (
	a, b, dout, con
);
	input signed [16:0] a, b;
	output signed [33:0] dout;
	input con;

	// 符号付き s17 x s17 = s34 ビット乗算
	assign dout = a * b;

endmodule
