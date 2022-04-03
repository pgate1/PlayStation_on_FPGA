
module mul_s10 (
	a, b, dout, con
);
	input signed [9:0] a, b;
	output signed [19:0] dout;
	input con;

	// •„†•t‚« s10 x s10 = s20
	assign dout = a * b;

endmodule
