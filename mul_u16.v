
module mul_u16 (
	a, b, dout, con
);
	input [15:0] a, b;
	output [31:0] dout;
	input con;

	// -> �����Ȃ� 16x16=32 �r�b�g��Z
	assign dout = a * b;

endmodule
