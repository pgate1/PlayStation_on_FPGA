
`default_nettype none

module PlayStation_top
(
	input wire RESET_N,
	////////////////////	Clock Input	 	////////////////////
	input wire CLOCK_50,  //	50 MHz
	input wire CLOCK2_50, //	50 MHz
	input wire CLOCK3_50, //	50 MHz
	input wire CLOCK4_50, //	50 MHz
	////////////////////	Push Button		////////////////////
	input wire [3:0] KEY, //	Pushbutton[3:0]
	////////////////////	DPDT Switch		////////////////////
	input wire [9:0] SW, //	Toggle Switch[9:0]
	////////////////////	7-SEG Dispaly	////////////////////
	output wire [6:0] HEX0, //	Seven Segment Digit 0
	output wire [6:0] HEX1, //	Seven Segment Digit 1
	output wire [6:0] HEX2,	//	Seven Segment Digit 2
	output wire [6:0] HEX3, //	Seven Segment Digit 3
	output wire [6:0] HEX4, //	Seven Segment Digit 4
	output wire [6:0] HEX5, //	Seven Segment Digit 5
	////////////////////////	LED		////////////////////////
	output wire [9:0] LEDR, //	LED Green[9:0]
	/////////////////////	SDRAM Interface		////////////////
	inout wire [15:0] DRAM_DQ, //	SDRAM Data bus 16 Bits
	output wire [12:0] DRAM_ADDR, //	SDRAM Address bus 13 Bits
	output wire DRAM_LDQM, //	SDRAM Low-byte Data Mask 
	output wire DRAM_UDQM, //	SDRAM High-byte Data Mask
	output wire DRAM_WE_N, //	SDRAM Write Enable
	output wire DRAM_CAS_N, //	SDRAM Column Address Strobe
	output wire DRAM_RAS_N, //	SDRAM Row Address Strobe
	output wire DRAM_CS_N, //	SDRAM Chip Select
	output wire [1:0] DRAM_BA, //	SDRAM Bank Address
	output wire DRAM_CLK, //	SDRAM Clock
	output wire DRAM_CKE, //	SDRAM Clock Enable
	////////////////////	SD_Card Interface	////////////////
	input wire [3:0] SD_DATA, //	SD Card Data
	inout wire SD_CMD, //	SD Card Command Signal
	output wire SD_CLK, //	SD Card Clock
	////////////////////	PS2		////////////////////////////
	input wire PS2_CLK, //	PS2 
	input wire PS2_DAT, //	PS2 
	input wire PS2_CLK2, //	PS2
	input wire PS2_DAT2, //	PS2
	////////////////////	VGA		////////////////////////////
	output wire VGA_HS, //	VGA H_SYNC
	output wire VGA_VS, //	VGA V_SYNC
	output wire [3:0] VGA_R, //	VGA Red[3:0]
	output wire [3:0] VGA_G, //	VGA Green[3:0]
	output wire [3:0] VGA_B, //	VGA Blue[3:0]
	////////////////////	GPIO	////////////////////////////
	inout wire [35:0] GPIO_0, //	GPIO Connection 0 Data Bus
	inout wire [35:0] GPIO_1  //	GPIO Connection 1 Data Bus
);

wire reset, g_reset;
wire clk_core, clk_100mhz;

wire sdram_write;
wire [24:0] sdram_adrs;
wire [127:0] sdram_din;
wire [15:0] sdram_enable;
wire [3:0] sdram_burst;
wire sdram_read;
wire [127:0] sdram_dout;
wire sdram_ack_100;

wire [15:0] sdram_Din;
wire sdram_Din_En;

wire sd_cmd_out, sd_cmd_en;

	sys_reset RSTU (
		.RSTn(RESET_N), .CLK(CLOCK_50), .DOUT(reset)
	);

	GLOBAL rst_GU (
		.IN(reset), .OUT(g_reset)
	);

	core CU (
		.p_reset(g_reset),
		.m_clock(clk_core),
		.KEY(KEY), // in std_logic_vector(3 downto 0);
		.SW(SW), // in std_logic_vector(9 downto 0);
		.HEX0(HEX0), //	Seven Segment Digit 0
		.HEX1(HEX1), //	Seven Segment Digit 1
		.HEX2(HEX2), //	Seven Segment Digit 2
		.HEX3(HEX3), //	Seven Segment Digit 3
		.HEX4(HEX4), //	Seven Segment Digit 4
		.HEX5(HEX5), //	Seven Segment Digit 5
		.LEDR(LEDR), // out std_logic_vector(9 downto 0))
//--------------------- SDRAM Interface --------------------
		.sdram_write(sdram_write),
		.sdram_adrs(sdram_adrs), .sdram_din(sdram_din), .sdram_enable(sdram_enable), .sdram_burst(sdram_burst),
		.sdram_read(sdram_read),
		.sdram_dout(sdram_dout), .sdram_ack_100(sdram_ack_100),
//--------------------- SD_Card Interface ------------------
//		SD_CSn => SD_DAT3, SD_CLK => SD_CLK, -- SPI mode
//		SD_CMD => SD_CMD,  SD_DAT => SD_DAT0 -- SPI mode
		.SD_CLK(SD_CLK), .SD_CMD_en(sd_cmd_en), // SD mode
		.SD_CMD(sd_cmd_out), .SD_RES(SD_CMD), .SD_DAT(SD_DATA), // SD mode
//--------------------- VGA --------------------------------
		.VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
		.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B)
//-------------------- PS/2 --------------------------------
//		.PS2_KBCLK(PS2_CLK), .PS2_KBDAT(PS2_DAT)
	);

	assign DRAM_CKE = 1'b1;
	sdram_pll_100 sdram_pll_100_inst (
		.refclk(CLOCK_50),
		.rst(0),
		.outclk_0(clk_core),
		.outclk_1(clk_100mhz),
		.outclk_2(DRAM_CLK),
		.locked()
	);
	assign DRAM_DQ = sdram_Din_En==1'b0 ? sdram_Din : 16'hzzzz;

	sdram128_burstn_ctrl_100 sdram_ctrl_inst (
		.p_reset(g_reset),
		.m_clock(clk_100mhz),
		.CSn(DRAM_CS_N),
		.RASn(DRAM_RAS_N),
		.CASn(DRAM_CAS_N),
		.WEn(DRAM_WE_N),
		.DQM({DRAM_UDQM, DRAM_LDQM}),
		.DEn(sdram_Din_En),
		.BA(DRAM_BA),
		.A(DRAM_ADDR),
		.Din(sdram_Din),
		.Dout(DRAM_DQ),
		.write(sdram_write),
		.adrs(sdram_adrs),
		.din(sdram_din),
		.enable(sdram_enable),
		.burst(sdram_burst),
		.read(sdram_read),
		.dout(sdram_dout),
		.manual_refresh(1'b0),
		.refresh_go(1'b0),
		.ack(sdram_ack_100)
	);

	assign GPIO_0 = 36'b0;
	assign GPIO_1 = 36'b0;

	// CMD SPI:コマンド出力、SD:コマンド出力とレスポンス入力
	assign SD_CMD = sd_cmd_en==1'b1 ? sd_cmd_out : 1'bz;

endmodule

`default_nettype wire
