
module mul_s16 (
	a, b, dout, con
);
	input signed [15:0] a, b;
	output signed [31:0] dout;
	input con;

	// -> �����t�� 16x16=32 �r�b�g��Z
	assign dout = a * b;

endmodule
