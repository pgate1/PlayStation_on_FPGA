
module mul_u32 (
	a, b, dout, con
);
	input [31:0] a, b;
	output [63:0] dout;
	input con;

	// -> �����Ȃ� 32x32=64 �r�b�g��Z
	assign dout = a * b;

endmodule
