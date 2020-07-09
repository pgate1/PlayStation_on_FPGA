
module mul_s18s16 (
	a, b, dout, con
);
	input signed [17:0] a;
	input signed [15:0] b;
	output signed [33:0] dout;
	input con;

	// •„†•t‚« s18 x s16 = s34
	assign dout = a * b;

endmodule
