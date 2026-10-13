// Interface of upstream DigitalSignalProcessor.sflp, for linking the time-shared
// SystemVerilog replacement (DigitalSignalProcessor_shared.sv). Clocked module:
// sflc adds p_reset/m_clock. Ports and argument lists match the original.
declare DigitalSignalProcessor
{
	input io_A<16>, io_Din<16>;
	output io_Dout<16>;
	instrin io_set;
	instr_arg io_set(io_A, io_Din);
	instrin io_get;
	instr_arg io_get(io_A);
	input CtrlRvb, CtrlIRQ;
	instrin run33;
	instrout read_req, write_req;
	output vA<18>, vDout<16>;
	input vDin<16>;
	instrin ack;
	input dma_doing;
	instrin sw_intpl_off, sw_reverb_off, sw_spuenv_off;
	output voice_out_L<21>, voice_out_R<21>;
	output disp_env<24>;
	output halt_code<8>;
	output dbg<32>;
}
