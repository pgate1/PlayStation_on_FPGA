
module mul_u8 (
	a, b, dout, con
);
	input [7:0] a, b;
	output [15:0] dout;
	input con;

	// -> �����Ȃ� 8x8=16 �r�b�g��Z
	assign dout = a * b;

endmodule
