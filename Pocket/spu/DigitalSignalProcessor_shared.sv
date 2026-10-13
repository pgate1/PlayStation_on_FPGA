// SPDX-License-Identifier: MIT
// Drop-in DigitalSignalProcessor built from the time-shared engine.
module DigitalSignalProcessor (
    input  wire p_reset, m_clock,
    input  wire io_set, input wire [15:0] io_A, io_Din, input wire io_get, output wire [15:0] io_Dout,
    input  wire CtrlRvb, CtrlIRQ, run33,
    output wire read_req, write_req, output wire [17:0] vA, output wire [15:0] vDout, input wire [15:0] vDin,
    input  wire ack, dma_doing, sw_intpl_off, sw_reverb_off, sw_spuenv_off,
    output wire [20:0] voice_out_L, voice_out_R, output wire [23:0] disp_env,
    output wire [7:0] halt_code, output wire [31:0] dbg);
    spu_dsp_shared u (.*);
endmodule
