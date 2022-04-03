
module bcd_itob(
	input [7:0] bin,
	output [7:0] bcd,
	input con
);

wire [7:0] bcd_0;
wire [7:0] bcd_1;

	assign bcd_0 = bin % 8'h0A;
	assign bcd_1 = bin / 8'h0A;

	assign bcd[3:0] = bcd_0[3:0];
	assign bcd[7:4] = bcd_1[3:0];

endmodule
