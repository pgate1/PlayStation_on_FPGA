
module bcd_btoi(
	input [7:0] bcd,
	output [7:0] bin,
	input con
);

	assign bin = ({4'h0, bcd[7:4]} * 8'h0A) + {4'h0, bcd[3:0]};

endmodule
