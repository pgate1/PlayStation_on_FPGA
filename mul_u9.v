
module mul_u9 (
	a, b, dout, con
);
	input [8:0] a, b;
	output [17:0] dout;
	input con;

	// -> �����Ȃ� 9x9=18 �r�b�g��Z
	assign dout = a * b;

endmodule
