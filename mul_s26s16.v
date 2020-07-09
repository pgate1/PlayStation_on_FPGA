
module mul_s26s16 (
	a, b, dout, con
);
	input signed [25:0] a;
	input signed [15:0] b;
	output signed [41:0] dout;
	input con;

	// •„†•t‚« s26 x s16 = s42
	assign dout = a * b;

endmodule
