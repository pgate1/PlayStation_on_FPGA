
module bcd_itob(
	input [7:0] bin,
	output [7:0] bcd,
	input con
);

	// Fast BCD conversion via reciprocal multiplication and shift-and-add:
	// Dividing by 10 is computed by multiplying by ceil(2^11 / 10) = 205 and shifting right by 11.
	// For all 8-bit values (0..255), (bin * 205) >> 11 matches floor(bin / 10) exactly.
	// The remainder (units digit) is obtained as bin - tens * 10.
	// Multiplying tens by 10 is implemented via constant wiring shifts:
	// tens * 10 = (tens * 8) + (tens * 2) = (tens << 3) + (tens << 1).
	// This avoids instantiating a multiplier for the remainder calculation,
	// reducing cell count and combinational propagation delay.
	wire [15:0] mul_res = bin * 8'd205;
	wire [3:0] tens = mul_res[14:11];
	wire [7:0] tens_x8 = {1'b0, tens, 3'b000};
	wire [7:0] tens_x2 = {3'b000, tens, 1'b0};
	wire [7:0] tens_x10 = tens_x8 + tens_x2;
	wire [7:0] units = bin - tens_x10;

	assign bcd[3:0] = units[3:0];
	assign bcd[7:4] = tens;

endmodule
