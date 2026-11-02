
module bcd_btoi(
	input [7:0] bcd,
	output [7:0] bin,
	input con
);

	// Fast BCD to binary conversion via shift-and-add:
	// Binary value = tens * 10 + units = (tens * 8 + tens * 2) + units
	// = (tens << 3) + (tens << 1) + units.
	// Implementing multiplication by 10 as constant wiring shifts avoids
	// instantiating general multiplication logic, reducing cell count and area.
	wire [7:0] tens_x8 = {1'b0, bcd[7:4], 3'b000};
	wire [7:0] tens_x2 = {3'b000, bcd[7:4], 1'b0};
	wire [7:0] units   = {4'b0000, bcd[3:0]};

	assign bin = (tens_x8 + tens_x2) + units;

endmodule
