// è‘‚«
// altera‚Årom‚É‚È‚é

module RateTableAdd_rom (
	m_clock, p_reset,
	adrs, dout,
	read
);
input m_clock, p_reset;
input [6:0] adrs;
output [13:0] dout;
input read;

	reg [13:0] dout;

	always @(posedge m_clock) begin
		case (adrs)
			7'h00 : dout <= 14336;
			7'h01 : dout <= 12288;
			7'h02 : dout <= 10240;
			7'h03 : dout <=  8192;
			7'h04 : dout <=  7168;
			7'h05 : dout <=  6144;
			7'h06 : dout <=  5120;
			7'h07 : dout <=  4096;
			7'h08 : dout <=  3584;
			7'h09 : dout <=  3072;
			7'h0A : dout <=  2560;
			7'h0B : dout <=  2048;
			7'h0C : dout <=  1792;
			7'h0D : dout <=  1536;
			7'h0E : dout <=  1280;
			7'h0F : dout <=  1024;
			7'h10 : dout <=   896;
			7'h11 : dout <=   768;
			7'h12 : dout <=   640;
			7'h13 : dout <=   512;
			7'h14 : dout <=   448;
			7'h15 : dout <=   384;
			7'h16 : dout <=   320;
			7'h17 : dout <=   256;
			7'h18 : dout <=   224;
			7'h19 : dout <=   192;
			7'h1A : dout <=   160;
			7'h1B : dout <=   128;
			7'h1C : dout <=   112;
			7'h1D : dout <=    96;
			7'h1E : dout <=    80;
			7'h1F : dout <=    64;
			7'h20 : dout <=    56;
			7'h21 : dout <=    48;
			7'h22 : dout <=    40;
			7'h23 : dout <=    32;
			7'h24 : dout <=    28;
			7'h25 : dout <=    24;
			7'h26 : dout <=    20;
			7'h27 : dout <=    16;
			7'h28 : dout <=    14;
			7'h29 : dout <=    12;
			7'h2A : dout <=    10;
			7'h2B : dout <=     8;
			7'h2C : dout <=     7;
			7'h2D : dout <=     6;
			7'h2E : dout <=     5;
			7'h2F : dout <=     4;
			7'h30 : dout <=     3;
			7'h31 : dout <=     3;
			7'h32 : dout <=     2;
			7'h33 : dout <=     2;
			7'h34 : dout <=     1;
			7'h35 : dout <=     1;
			7'h36 : dout <=     1;
			7'h37 : dout <=     1;
			7'h38 : dout <=     0;
			7'h39 : dout <=     0;
			7'h3A : dout <=     0;
			7'h3B : dout <=     0;
			7'h3C : dout <=     0;
			7'h3D : dout <=     0;
			7'h3E : dout <=     0;
			7'h3F : dout <=     0;
			7'h40 : dout <=     0;
			7'h41 : dout <=     0;
			7'h42 : dout <=     0;
			7'h43 : dout <=     0;
			7'h44 : dout <=     0;
			7'h45 : dout <=     0;
			7'h46 : dout <=     0;
			7'h47 : dout <=     0;
			7'h48 : dout <=     0;
			7'h49 : dout <=     0;
			7'h4A : dout <=     0;
			7'h4B : dout <=     0;
			7'h4C : dout <=     0;
			7'h4D : dout <=     0;
			7'h4E : dout <=     0;
			7'h4F : dout <=     0;
			7'h50 : dout <=     0;
			7'h51 : dout <=     0;
			7'h52 : dout <=     0;
			7'h53 : dout <=     0;
			7'h54 : dout <=     0;
			7'h55 : dout <=     0;
			7'h56 : dout <=     0;
			7'h57 : dout <=     0;
			7'h58 : dout <=     0;
			7'h59 : dout <=     0;
			7'h5A : dout <=     0;
			7'h5B : dout <=     0;
			7'h5C : dout <=     0;
			7'h5D : dout <=     0;
			7'h5E : dout <=     0;
			7'h5F : dout <=     0;
			7'h60 : dout <=     0;
			7'h61 : dout <=     0;
			7'h62 : dout <=     0;
			7'h63 : dout <=     0;
			7'h64 : dout <=     0;
			7'h65 : dout <=     0;
			7'h66 : dout <=     0;
			7'h67 : dout <=     0;
			7'h68 : dout <=     0;
			7'h69 : dout <=     0;
			7'h6A : dout <=     0;
			7'h6B : dout <=     0;
			7'h6C : dout <=     0;
			7'h6D : dout <=     0;
			7'h6E : dout <=     0;
			7'h6F : dout <=     0;
			7'h70 : dout <=     0;
			7'h71 : dout <=     0;
			7'h72 : dout <=     0;
			7'h73 : dout <=     0;
			7'h74 : dout <=     0;
			7'h75 : dout <=     0;
			7'h76 : dout <=     0;
			7'h77 : dout <=     0;
			7'h78 : dout <=     0;
			7'h79 : dout <=     0;
			7'h7A : dout <=     0;
			7'h7B : dout <=     0;
			7'h7C : dout <=     0;
			7'h7D : dout <=     0;
			7'h7E : dout <=     0;
			7'h7F : dout <=     0;
			default: dout <= 0;
		endcase
	end

endmodule
