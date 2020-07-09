// PSX PlayStation on FPGA .feat DE2-115
// Copyright (c)2017 pgate1

module PSX_top
(
	input wire CLOCK_50, CLOCK2_50, CLOCK3_50, ENETCLK_25,
	output wire [8:0] LEDG, // LED Green '1'light
	output wire [17:0] LEDR, // LED Red   '1'light
	input wire [3:0] KEY, // Pushbutton : push'0'
	input wire [17:0] SW, // Toggle Switch : up'1'
	output wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7, // Seven Segment Digit : '0'light
//--------------------- SRAM Interface ---------------------
	inout wire [15:0] SRAM_DQ,
	output wire [19:0] SRAM_ADDR,
	output wire SRAM_LB_N, SRAM_UB_N,
	output wire SRAM_CE_N, SRAM_OE_N, SRAM_WE_N,
//--------------------- SDRAM Interface --------------------
	inout wire [31:0] DRAM_DQ,
	output wire [1:0] DRAM_BA,
	output wire [12:0] DRAM_ADDR,
	output wire [3:0] DRAM_DQM,
	output wire DRAM_CKE, DRAM_CLK,
	output wire DRAM_RAS_N, DRAM_CAS_N,
	output wire DRAM_CS_N,  DRAM_WE_N,
//--------------------- Flash Memory -----------------------
	output wire [22:0] FL_ADDR,
	inout wire [7:0] FL_DQ,
	output wire FL_RST_N, FL_CE_N,
	output wire FL_OE_N, FL_WE_N,
	input wire FL_RY,
	output wire FL_WP_N,
//--------------------- VGA --------------------------------
	output wire VGA_CLK, VGA_SYNC_N, VGA_BLANK_N, VGA_HS, VGA_VS,
	output wire [7:0] VGA_R, VGA_G, VGA_B,
//--------------------- Audio CODEC ------------------------
	inout wire AUD_ADCLRCK, // ADC LR Clock
	input wire AUD_ADCDAT, // ADC Data
	inout wire AUD_DACLRCK, // DAC LR Clock
	output wire AUD_DACDAT, // DAC Data
	inout wire AUD_BCLK, // Bit-Stream Clock
	output wire AUD_XCK, // Chip Clock
//--------------------- I2C --------------------------------
	output wire I2C_SCLK,
	inout wire I2C_SDAT,
//--------------------- SD_Card Interface ------------------
	output wire SD_CLK, // SD Card Clock
	inout wire SD_CMD, // SD Card Command & Dout
	input wire SD_WP_N,
	input wire [3:0] SD_DAT, // SD Card Data
//--------------------- IR Receiver ------------------------
	input wire IRDA_RXD,
//--------------------- USB ISP1362 ------------------------
	output wire [1:0] OTG_ADDR,
	inout wire [15:0] OTG_DATA,
	output wire OTG_CS_N, OTG_RST_N,
	output wire OTG_RD_N, OTG_WR_N,
	input wire [1:0] OTG_INT,
	output wire [1:0] OTG_DACK_N,
	input wire [1:0] OTG_DREQ,
	inout wire OTG_FSPEED, OTG_LSPEED,
//--------------------- LCD --------------------------------
	output wire LCD_ON, LCD_BLON,
	output wire LCD_RS, LCD_RW, LCD_EN,
	output wire [7:0] LCD_DATA,
//--------------------- PS/2 -------------------------------
	input wire PS2_CLK,	// PS2
	input wire PS2_DAT, // PS2
	input wire PS2_CLK2, // PS2
	input wire PS2_DAT2, // PS2
//----------------------------------------------------------
	inout wire [3:0] GPIO
);

wire p_reset, g_reset;

wire clk100mhz;

wire [15:0] sram_Dout;
wire sram_Dout_En;

wire sdram_write;
wire [24:0] sdram_adrs;
wire [31:0] sdram_wdata;
wire [3:0] sdram_de;
wire sdram_read;
wire [31:0] sdram_rdata;
wire sdram_ack, sdram_err;
wire [31:0] sdram_Dout;
wire sdram_Dout_En;

wire g_reset_n, CLK_18_4;
wire audio_RD;
wire [31:0] audio_DATA;
wire [6:0] audio_VOL;
wire audio_SET;

wire [15:0] usb_Dout;
wire usb_WR_En;

wire sd_cmd_out, sd_cmd_en;

	sys_reset RSTU (
		.RSTn(KEY[0]), .CLK(CLOCK_50), .DOUT(p_reset)
	);

	global RSTGU (
		.IN(p_reset), .OUT(g_reset)
	);

	core CU (
		.p_reset(g_reset), .m_clock(CLOCK_50),
		.KEY(KEY), .SW(SW),
		.LEDR(LEDR), .LEDG(LEDG),
		.HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
		.HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7),
//--------------------- SRAM Interface ---------------------
		.SRAM_CEn(SRAM_CE_N), .SRAM_OEn(SRAM_OE_N), .SRAM_WEn(SRAM_WE_N),
		.SRAM_LBn(SRAM_LB_N), .SRAM_UBn(SRAM_UB_N), .SRAM_DEn(sram_Dout_En),
		.SRAM_ADDR(SRAM_ADDR),
		.SRAM_Din(SRAM_DQ), .SRAM_Dout(sram_Dout),
//--------------------- SDRAM Interface --------------------
//		.SDRAM_CSn(DRAM_CS_N), .SDRAM_WEn(DRAM_WE_N), .SDRAM_DEn(sdram_Dout_En),
//		.SDRAM_RASn(DRAM_RAS_N), .SDRAM_CASn(DRAM_CAS_N),
//		.SDRAM_BA(DRAM_BA), .SDRAM_ADDR(DRAM_ADDR),
//		.SDRAM_DQM(DRAM_DQM), .SDRAM_Din(DRAM_DQ), .SDRAM_Dout(sdram_Dout),
		.sdram_write(sdram_write), .sdram_wdata(sdram_wdata), .sdram_de(sdram_de),
		.sdram_adrs(sdram_adrs), .sdram_read(sdram_read), .sdram_rdata(sdram_rdata),
		.sdram_ack(sdram_ack), .sdram_err(sdram_err),
//--------------------- Flash Interface --------------------
		.FLASH_RSTn(FL_RST_N), .FLASH_CEn(FL_CE_N),
		.FLASH_OEn(FL_OE_N), .FLASH_WEn(FL_WE_N),
		.FLASH_ADDR(FL_ADDR), .FLASH_Din(FL_DQ),
//--------------------- VGA --------------------------------
		.VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_BLANKn(VGA_BLANK_N),
		.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
//--------------------- Audio ------------------------
		.audio_RD(audio_RD), .audio_DATA(audio_DATA),
		.audio_SET(audio_SET), .audio_VOL(audio_VOL),
//--------------------- SD_Card Interface ------------------
		.SD_CLK(SD_CLK), .SD_CMD_en(sd_cmd_en), // SD mode
		.SD_CMD(sd_cmd_out), .SD_RES(SD_CMD), .SD_DAT(SD_DAT), // SD mode
//--------------------- USB ISP1362 ------------------------
		.USB_ADDR(OTG_ADDR), .USB_Dout(usb_Dout),
		.USB_WRn(usb_WR_En), .USB_RDn(OTG_RD_N),
		.USB_Din(OTG_DATA),
//--------------------- LCD --------------------------------
		.LCD_RS(LCD_RS), .LCD_RW(LCD_RW), .LCD_EN(LCD_EN),
		.LCD_DATA(LCD_DATA)
	);

	assign SRAM_DQ = sram_Dout_En==1'b0 ? sram_Dout : 16'hzzzz;

	assign DRAM_CKE = 1'b1;
	sdram_pll_100 sdram_pll_inst (
		.inclk0(CLOCK_50), .c0(DRAM_CLK), .c1(clk100mhz)
	);

	sdram_ctrl_100 sdram_ctrl_100_inst (
		.p_reset(g_reset),
		.m_clock(clk100mhz),
		.CSn(DRAM_CS_N),
		.RASn(DRAM_RAS_N),
		.CASn(DRAM_CAS_N),
		.WEn(DRAM_WE_N),
		.DQM(DRAM_DQM),
		.DEn(sdram_Dout_En),
		.BA(DRAM_BA),
		.A(DRAM_ADDR),
		.Din(DRAM_DQ),
		.Dout(sdram_Dout),
		.write(sdram_write),
		.wdata(sdram_wdata),
		.adrs(sdram_adrs),
		.enable(sdram_de),
		.read(sdram_read),
		.rdata(sdram_rdata),
		.ack(sdram_ack),
		.err(sdram_err)
	);

	assign DRAM_DQ = sdram_Dout_En==1'b0 ? sdram_Dout : 32'hzzzzzzzz;

	assign FL_WP_N = 1'b1;
	assign FL_DQ = 8'hzz;

	assign VGA_CLK = ~CLOCK_50;
	assign VGA_SYNC_N = 1'b1;

	assign g_reset_n = ~g_reset;

	I2C_AV_Config DACConfU (
		.iCLK(CLOCK_50), .iRST_N(g_reset_n),
		.iVOL(audio_VOL), .iSET(audio_SET),
		.I2C_SCLK(I2C_SCLK), .I2C_SDAT(I2C_SDAT)
	);

	// make 18.4MHz
	audio_pll audio_pll_inst (
		.inclk0(CLOCK_50), .c0(CLK_18_4)
	);

	AUDIO_ctrl AU (
		.iRST_N(g_reset_n), .iCLK_18_4(CLK_18_4),
		.iDATA_RD(audio_RD), .iDATA(audio_DATA),
		.oAUD_BCK(AUD_BCLK), .oAUD_DATA(AUD_DACDAT),
		.oAUD_LRCK(AUD_DACLRCK), .oAUD_XCK(AUD_XCK)
	);

	assign OTG_DATA = usb_WR_En==1'b0 ? usb_Dout : 16'hzzzz;
	assign OTG_WR_N = usb_WR_En;
	assign OTG_CS_N = 1'b0;
	assign OTG_RST_N = g_reset_n;
	assign OTG_DACK_N = OTG_DREQ;
	assign OTG_FSPEED = 1'b1;
	assign OTG_LSPEED = 1'b0;

	// CMD SPI:コマンド出力、SD:コマンド出力とレスポンス入力
	assign SD_CMD = (sd_cmd_en==1'b1) ? sd_cmd_out : 1'bz;

	assign LCD_ON = 1'b1;
	assign LCD_BLON = 1'b0; // 1でも光らない

endmodule
