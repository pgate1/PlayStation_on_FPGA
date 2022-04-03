
module compare_s11 (
	a, b, gt, lt, gte, lte, result
);
	input signed [10:0] a, b;
	input gt, lt, gte, lte;
	output wire result;

	assign result =
		(gt & (a > b)) |
		(lt & (a < b)) |
		(gte & (a >= b)) |
		(lte & (a <= b));

/*
	output reg result;
	always @* begin
		case (1'b1)
			gt : result = a > b;
			lt : result = a < b;
			gte : result = a >= b;
			lte : result = a <= b;
		endcase
	end
*/
endmodule
