//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 1;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the rest of the pins we are not using
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;
/*
assign dram_a = 'h0;
assign dram_ba = 'h0;
assign dram_dq = {16{1'bZ}};
assign dram_dqm = 'h0;
assign dram_clk = 'h0;
assign dram_cke = 'h0;
assign dram_ras_n = 'h1;
assign dram_cas_n = 'h1;
assign dram_we_n = 'h1;
*/
assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


// for bridge write data, we just broadcast it to all bus devices
// for bridge read data, we have to mux it
// add your own devices here
always @(*) begin
    casex(bridge_addr)
    default: begin
        // all unmapped addresses are zero
        bridge_rd_data <= 0;
    end
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    endcase
end


//
// host/target command handler
//
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;
    
// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked; 
    wire            status_setup_done = pll_core_locked; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;
    
    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    wire            savestate_supported;
    wire    [31:0]  savestate_addr;
    wire    [31:0]  savestate_size;
    wire    [31:0]  savestate_maxloadsize;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;
    
    wire            osnotify_inmenu;

// bridge target commands
// synchronous to clk_74a

    reg             target_dataslot_read;       
    reg             target_dataslot_write;

    wire            target_dataslot_ack;        
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    reg     [15:0]  target_dataslot_id;
    reg     [31:0]  target_dataslot_slotoffset;
    reg     [31:0]  target_dataslot_bridgeaddr;
    reg     [31:0]  target_dataslot_length;
    
// bridge data slot access
// synchronous to clk_74a

    wire    [9:0]   datatable_addr;
    wire            datatable_wren;
    wire    [31:0]  datatable_data;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                    ( clk_74a ),
    .reset_n                ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),
    
    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),
    
    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),
    
    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),
    
    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),

    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);



//  reg             ram1_word_rd;
    reg             ram1_word_wr;
    reg     [23:0]  ram1_word_addr;
    reg     [1:0]   ram1_word_wrmask;
    reg     [31:0]  ram1_word_data;
//  wire    [31:0]  ram1_word_q;
//  wire            ram1_word_busy;

	reg             bram_word_wr;

   reg     [2:0]   reload_state;
   reg             ram_reloading;

   wire    [15:0]  target_id;
   wire    [31:0]  target_slotoffset;
   wire    [31:0]  target_bridgeaddr;
   wire    [31:0]  target_length;
   
   reg set_sdram_in, set_bram_in;
   
   wire set_sdram, set_sdram_s, set_sdram_r;
synch_3 s_setsdram(set_sdram, set_sdram_s, clk_74a, set_sdram_r);
   wire set_bram, set_bram_s, set_bram_r;
synch_3 s_setbram(set_bram, set_bram_s, clk_74a, set_bram_r);

initial begin
	set_sdram_in <= 0;
	set_bram_in <= 0;

    ram_reloading <= 0;
    
    reload_state <= 0;
    target_dataslot_read <= 0;
end


always @(posedge clk_74a) begin
    ram1_word_wr <= 0;
    bram_word_wr <= 0;
    // handle memory mapped I/O from pocket

    if(bridge_wr) begin
        casex(bridge_addr[31:24])
        8'b000000xx: begin
            // 64mbyte sdram mapped at 0x0

            // the ram controller's word port is 32bit aligned
            if(set_sdram_in) ram1_word_wr <= 1;
            if(set_bram_in) bram_word_wr <= 1;

            ram1_word_wrmask <= 2'b00;
            ram1_word_addr <= bridge_addr[25:2];
            ram1_word_data <= bridge_wr_data;
        end
        endcase
    end

    case(reload_state)
    0: begin
        if(set_sdram_r | set_bram_r) begin
        	if(set_sdram_r) set_sdram_in <= 1;
        	if(set_bram_r) set_bram_in <= 1;

            ram_reloading <= 1;

            // start the command
            target_dataslot_id <= target_id;
            target_dataslot_slotoffset <= target_slotoffset;
            target_dataslot_bridgeaddr <= target_bridgeaddr;
            target_dataslot_length <= target_length;
            target_dataslot_read <= 1;

            reload_state <= 1;
        end

    end
    1: begin
        // wait for ack
        if(target_dataslot_ack) begin
            target_dataslot_read <= 0;
        //    target_dataslot_write <= 0;
            
            reload_state <= 2;
        end
    end
    2: begin
        if(target_dataslot_done) begin
        	set_sdram_in <= 0;
        	set_bram_in <= 0;

            ram_reloading <= 0;
            
            reload_state <= 0;
        end
    end
    endcase

end

   wire target_dataslot_read_s;
synch_3 sread(target_dataslot_read, target_dataslot_read_s, clk_50);
   wire ram_reloading_s;
synch_3 sreload(ram_reloading, ram_reloading_s, clk_50);


    wire word_wr_s, word_wr_r;
synch_3 s3(ram1_word_wr, word_wr_s, dram_ctrl_clk, word_wr_r);


	reg [1:0] bram_word_wr_hold;
always @(negedge reset_n or posedge clk_74a) begin
	if(reset_n==1'b0) begin
		bram_word_wr_hold <= 0;
	end
	else if(bram_word_wr) begin
		bram_word_wr_hold <= 1;
	end
	else if(bram_word_wr_hold!=0) begin
		bram_word_wr_hold <= bram_word_wr_hold + 1;
	end
end

	wire bram_word_wr_hold_s, bram_word_wr_hold_r;
synch_3 swrhold(|bram_word_wr_hold, bram_word_wr_hold_s, clk_50, bram_word_wr_hold_r);

	wire [15:0] key_s;
synch_3 #(.WIDTH(16)) synch_controler(cont1_key[15:0], key_s, clk_50);

////////////////////////////////////////////////////////////////////////////////////////

	wire [15:0] dram_Dout;
	wire dram_Dout_En;

	wire sdram_write;
	wire [23:0] sdram_adrs;
	wire [31:0] sdram_wdata;
	wire [3:0] sdram_enable;
	wire sdram_read;
	wire [31:0] sdram_rdata;
	wire sdram_ack;

	core CU (
		.p_reset(~reset_n),
		.m_clock(clk_50),
//--------------------- Pad --------------------------------
		.key(key_s),
//--------------------- SDRAM Interface --------------------
		.sdram_write(sdram_write), .sdram_wdata(sdram_wdata), .sdram_enable(sdram_enable),
		.sdram_adrs(sdram_adrs), .sdram_read(sdram_read), .sdram_rdata(sdram_rdata),
		.sdram_ack_100(sdram_ack),
		
//--------------------- VGA --------------------------------
		.VGA_HS(video_hs), .VGA_VS(video_vs), .VGA_DE(video_de),
		.VGA_R(video_rgb[23:16]), .VGA_G(video_rgb[15:8]), .VGA_B(video_rgb[7:0]),
		
		.set_sdram(set_sdram), .set_bram(set_bram),
		.target_id(target_id), .target_slotoffset(target_slotoffset),
		.target_bridgeaddr(target_bridgeaddr), .target_length(target_length),
		.bram_word_wr(bram_word_wr_hold_r), .bram_wdata(ram1_word_data),
		.target_dataslot_read(target_dataslot_read_s), .ram_reloading(ram_reloading_s)
	);

	assign dram_cke = 1'b1;
	assign dram_dq = dram_Dout_En==1'b0 ? dram_Dout : 16'hzzzz;

	sdram32_burst2_ctrl_100 sdram_ctrl_inst (
		.p_reset(~pll_core_locked),
		.m_clock(dram_ctrl_clk),
		.RASn(dram_ras_n),
		.CASn(dram_cas_n),
		.WEn(dram_we_n),
		.DQM(dram_dqm),
		.DEn(dram_Dout_En),
		.BA(dram_ba),
		.A(dram_a),
		.Din(dram_dq),
		.Dout(dram_Dout),

		.write(word_wr_r | sdram_write),
		.wdata( ({32{word_wr_r}} & ram1_word_data) | ({32{sdram_write}} & sdram_wdata) ),
		.adrs( ({24{word_wr_r}} & ram1_word_addr) | ({24{sdram_write | sdram_read}} & sdram_adrs) ),
		.enable( ({4{word_wr_r}} & 4'b1111) | ({4{sdram_write}} & sdram_enable) ),
		.read(sdram_read),
		.rdata(sdram_rdata),
		.ack(sdram_ack)
	);


assign video_rgb_clock = clk_25;
assign video_rgb_clock_90 = clk_25_90deg;
//assign video_rgb = vidout_rgb;
//assign video_de = vidout_de;
assign video_skip = 0;//vidout_skip;
//assign video_vs = vidout_vs;
//assign video_hs = vidout_hs;


///////////////////////////////////////////////

	wire clk_50;
	wire dram_ctrl_clk;
    wire clk_25;
    wire clk_25_90deg;
    wire pll_core_locked;

	main_pll_0002 mpll (
		.refclk(clk_74a),
		.rst(0),

		.outclk_0(clk_50),

		.outclk_1(dram_ctrl_clk),
		.outclk_2(dram_clk),

		.outclk_3(clk_25),
		.outclk_4(clk_25_90deg),

		.locked(pll_core_locked)
	);


endmodule
