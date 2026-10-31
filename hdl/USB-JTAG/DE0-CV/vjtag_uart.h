
// vjtag_uart.h

declare vjtag_uart
{
	instrout recv_init, recv;
	output recv_data<8>;

	instrout send_init, send_ready;
	instrin send;
	input send_data<8>;

	instr_arg send(send_data);
}
