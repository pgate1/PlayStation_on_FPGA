/*
	Data transmission and reception with VirtualJTAG
*/

module vjtag_uart (
	input  wire p_reset,
	input  wire m_clock,
	output wire recv_init,
	output wire recv,
	output wire [7:0] recv_data,
	output wire send_init,
	output wire send_ready,
	input  wire send,
	input  wire [7:0] send_data
);

	wire [7:0] ir_in;
	wire tck, tdi, tdo;
	wire virtual_state_sdr, virtual_state_uir;

	VirtualJTAG vjtag (
		.tdo(tdo),
		.ir_in(ir_in),
		.tck(tck),
		.tdi(tdi),
		.virtual_state_sdr(virtual_state_sdr),
		.virtual_state_uir(virtual_state_uir)
	);

	localparam COMMAND_RECV = 8'h41;
	localparam COMMAND_SEND = 8'h42;

	reg t_init, t_recv, t_send;
	reg [7:0] ir, dr, ds;
	reg [2:0] count;

	always @(posedge p_reset or posedge tck) begin
		if(p_reset) begin
			t_init <= 0;
			t_recv <= 0;
			t_send <= 0;
		end
		else if(virtual_state_uir) begin
			ir <= ir_in;
			t_init <= 1;
		end	
		else if(t_init) begin
			count <= 0;
			if(ir==COMMAND_SEND) t_send <= 1;
			t_init <= 0;
		end
		else if(virtual_state_sdr) begin
			dr[count] <= tdi;
			count <= count + 1;
			if(count==7) begin
				if(ir==COMMAND_RECV) t_recv <= 1;
				if(ir==COMMAND_SEND) t_send <= 1;
			end
			else begin
				if(ir==COMMAND_RECV) t_recv <= 0;
				if(ir==COMMAND_SEND) t_send <= 0;
			end
		end
	end

	// t_init synchronizing
	reg [2:0] m_init;
	always @(posedge p_reset or posedge m_clock) begin
		if(p_reset)
			m_init <= 3'b000;
		else
			m_init <= {m_init[1:0], t_init};
	end

	// rising edge detection
	assign recv_init = (ir==COMMAND_RECV && m_init[2:1]==2'b01) ? 1 : 0;
	assign send_init = (ir==COMMAND_SEND && m_init[2:1]==2'b01) ? 1 : 0;

	// t_recv synchronizing
	reg [2:0] m_recv;
	always @(posedge p_reset or posedge m_clock) begin
		if(p_reset)
			m_recv <= 3'b000;
		else
			m_recv <= {m_recv[1:0], t_recv};
	end

	assign recv_data = dr;
	assign recv = m_recv[2:1]==2'b01 ? 1 : 0;

	// t_send synchronizing
	reg [2:0] m_send;
	always @(posedge p_reset or posedge m_clock) begin
		if(p_reset)
			m_send <= 3'b000;
		else
			m_send <= {m_send[1:0], t_send};
	end

	assign send_ready = m_send[2:1]==2'b01 ? 1 : 0;

	always @(posedge p_reset or posedge m_clock) begin
		if(p_reset)
			ds <= 8'h00;
		else if(send)
			ds <= send_data;
	end

	assign tdo = ds[count];

endmodule
