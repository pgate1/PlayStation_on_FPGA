
module mul_s32 (
	a, b, dout, con
);
	input signed [31:0] a, b;
	output signed [63:0] dout;
	input con;

	// �����t�� s32 x s32 = s64 �r�b�g��Z
	assign dout = a * b;

endmodule
