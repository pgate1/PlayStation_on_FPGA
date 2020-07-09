
module mul_s16s8 (
	a, b, dout, con
);
	input signed [15:0] a;
	input signed [7:0] b;
	output signed [23:0] dout;
	input con;

	// -> �����t�� s16 x s8 = 24 �r�b�g��Z
	assign dout = a * b;

endmodule
