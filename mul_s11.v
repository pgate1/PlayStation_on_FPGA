
module mul_s11 (
	a, b, dout, con
);
	input signed [10:0] a, b;
	output signed [21:0] dout;
	input con;

	// •„†•t‚« s11 x s11 = s22
	assign dout = a * b;

endmodule
