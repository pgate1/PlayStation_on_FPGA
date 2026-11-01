
module bcd_itob(
	input [7:0] bin,
	output [7:0] bcd,
	input con
);

	// Fast BCD conversion via reciprocal multiplication:
	// Dividing by 10 is computed by multiplying by ceil(2^11 / 10) = 205 and shifting right by 11.
	// For all 8-bit values (0..255), (bin * 205) >> 11 matches floor(bin / 10) exactly.
	// The remainder (units digit) is then obtained as bin - tens * 10.
	// This avoids generic division/modulo logic, reducing the longest combinational path.
	wire [15:0] mul_res = bin * 8'd205;
	wire [3:0] tens = mul_res[14:11];
	wire [7:0] units = bin - ({4'd0, tens} * 8'd10);

	assign bcd[3:0] = units[3:0];
	assign bcd[7:4] = tens;

endmodule
