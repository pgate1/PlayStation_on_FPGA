
module mul_s17 (
	a, b, dout, con
);
	input signed [16:0] a, b;
	output signed [33:0] dout;
	input con;

	// �����t�� s17 x s17 = s34 �r�b�g��Z
	assign dout = a * b;

endmodule
