// SPDX-License-Identifier: MIT
// Time-shared replacement for upstream DigitalSignalProcessor.sflp (24 x dsp_ch).
//
// Same ports and CPU/memory protocol as the sflc-generated DigitalSignalProcessor.
// One voice datapath (two shared multipliers, one set of ADSR rate ROMs) visits
// the 24 voices round-robin; per-voice state lives in small RAMs. Algorithms
// follow dsp_ch.sflp / ADSR.sflp: BRR decode, ADSR state machine and volume are
// bit-for-bit the same; key on/off and the 176.4 kHz tick are applied in the
// same tick order (events carry the tick count at which they happened).
// Deliberate difference: interpolation is evaluated once per 44.1 kHz output
// sample from the pitch counter (pre1 + (pre0 - pre1) * frac), instead of
// dsp_ch's per-clock ramp. disp_env (debug LEDs) is driven 0.
// See docs/POCKET_SPU_SHARED.md.
module spu_dsp_shared (
    input  wire        p_reset, m_clock,
    input  wire        io_set,
    input  wire [15:0] io_A, io_Din,
    input  wire        io_get,
    output logic [15:0] io_Dout,
    input  wire        CtrlRvb, CtrlIRQ,
    input  wire        run33,
    output logic       read_req, write_req,
    output logic [17:0] vA,
    output logic [15:0] vDout,
    input  wire [15:0] vDin,
    input  wire        ack, dma_doing,
    input  wire        sw_intpl_off, sw_reverb_off, sw_spuenv_off,
    output logic [20:0] voice_out_L, voice_out_R,
    output logic [23:0] disp_env,
    output logic [7:0]  halt_code,
    output logic [31:0] dbg
);
    localparam int NV = 24;
    // Per-voice CPU register slots (io_A[3:1]); slot 6 (0xC, current ADSR) is not stored.
    localparam logic [2:0] R_VOLL = 3'd0, R_VOLR = 3'd1, R_PITCH = 3'd2, R_START = 3'd3,
                           R_ADS = 3'd4, R_SR = 3'd5, R_LOOP = 3'd7;

    // ------------------------------------------------------------------
    // Tick generation (DigitalSignalProcessor.sflp run33 block)
    // ------------------------------------------------------------------
    logic [7:0] dcount;
    logic [2:0] rcount;
    logic [7:0] tick_cnt;          // number of 176.4 kHz ticks so far (mod 256)
    logic       rvb_run;
    always @(posedge m_clock) begin
        if (p_reset) begin dcount <= 8'd1; rcount <= '0; tick_cnt <= '0; end
        else if (run33) begin
            if (dcount == 8'd192) begin
                dcount <= 8'd1; rcount <= rcount + 3'd1; tick_cnt <= tick_cnt + 8'd1;
            end else dcount <= dcount + 8'd1;
        end
    end
    assign rvb_run = run33 && dcount == 8'd192 && &rcount && !sw_reverb_off;

    // ------------------------------------------------------------------
    // CPU register decode
    // ------------------------------------------------------------------
    wire [11:0] page   = io_A[15:4];
    wire        vpage  = page >= 12'h1C0 && page <= 12'h1D7;
    wire [4:0]  cpu_v  = page[4:0];   // 0x1C0 has zero low bits: page 0x1C0+v -> v
    wire [2:0]  cpu_r  = io_A[3:1];
    wire        a_mvl = io_A == 16'h1D80, a_mvr = io_A == 16'h1D82;
    wire        a_kon0 = io_A == 16'h1D88, a_kon1 = io_A == 16'h1D8A;
    wire        a_kof0 = io_A == 16'h1D8C, a_kof1 = io_A == 16'h1D8E;
    wire        a_ron0 = io_A == 16'h1D98, a_ron1 = io_A == 16'h1D9A;
    wire        a_rvbio = io_A == 16'h1D84 || io_A == 16'h1D86 || io_A == 16'h1DA2 ||
                          io_A[15:6] == 10'b0001_1101_11;
    wire        a_ign  = io_A == 16'h1D9C || io_A == 16'h1D9E || io_A == 16'h1DA4;
    wire        a_named_set = a_mvl | a_mvr | a_kon0 | a_kon1 | a_kof0 | a_kof1 |
                              a_ron0 | a_ron1 | a_rvbio | a_ign;
    wire        cpu_pwe = io_set && !a_named_set && vpage && !io_A[0] && cpu_r != 3'd6;
    wire [23:0] kon_bits = a_kon0 ? {8'd0, io_Din} : a_kon1 ? {io_Din[7:0], 16'd0} : 24'd0;
    wire [23:0] kof_bits = a_kof0 ? {8'd0, io_Din} : a_kof1 ? {io_Din[7:0], 16'd0} : 24'd0;
    wire [23:0] kon_ev = io_set ? kon_bits : 24'd0;
    wire [23:0] kof_ev = io_set ? kof_bits : 24'd0;

    logic [15:0] main_volume_L, main_volume_R;
    logic [23:0] rvb_on;
    logic [7:0]  halt_code_reg;
    logic [31:0] dbg_reg;
    always @(posedge m_clock) begin
        if (p_reset) begin
            main_volume_L <= '0; main_volume_R <= '0; rvb_on <= '0;
            halt_code_reg <= '0; dbg_reg <= '0;
        end else begin
            // Q-L1-16: the upstream DSP's halt on an unmapped register access (0x23 write, 0x24 read) was a
            // one-way debug stop that froze the whole core (hardware, Umihara menu). It is a one-cycle pulse
            // now: PlayStation_core latches `dbg` (the address) while it is high, then the core runs on.
            halt_code_reg <= '0;
            if (io_set && a_mvl) main_volume_L <= io_Din;
            if (io_set && a_mvr) main_volume_R <= io_Din;
            if (io_set && a_ron0) rvb_on[15:0] <= io_Din;
            if (io_set && a_ron1) rvb_on[23:16] <= io_Din[7:0];
            if (io_set && !a_named_set && !vpage) begin dbg_reg <= {16'd0, io_A}; halt_code_reg <= 8'h23; end
            if (io_get && !(a_mvl | a_mvr | a_ron0 | a_ron1) && !vpage) halt_code_reg <= 8'h24;
        end
    end
    assign halt_code = halt_code_reg;
    assign dbg = dbg_reg;
    assign disp_env = '0;

    // ------------------------------------------------------------------
    // Per-voice parameter RAMs: one write port, three asynchronous read ports
    // (CPU readback, engine, fetch). Stored values are masked like dsp_ch.
    // ------------------------------------------------------------------
    logic        fetch_lwe;            // fetch unit copies a loop address
    logic [4:0]  fetch_lv;
    logic [15:0] fetch_ldata;
    wire  [15:0] cpu_pdata = cpu_r == R_VOLL || cpu_r == R_VOLR ? {1'b0, io_Din[14:0]} :
                             cpu_r == R_PITCH ? {2'b0, io_Din[13:0]} : io_Din;
    wire         pwe    = cpu_pwe || fetch_lwe;
    wire  [7:0]  pwaddr = cpu_pwe ? {cpu_v, cpu_r} : {fetch_lv, R_LOOP};
    wire  [15:0] pwdata = cpu_pwe ? cpu_pdata : fetch_ldata;
    (* ramstyle = "MLAB, no_rw_check" *) logic [15:0] pram_cpu [0:255];
    (* ramstyle = "MLAB, no_rw_check" *) logic [15:0] pram_eng [0:255];
    // Fetch unit needs start and loop addresses at the same time: one RAM each
    // (Quartus 25.1 crashes splitting a RAM with two asynchronous read ports).
    (* ramstyle = "MLAB, no_rw_check" *) logic [15:0] fet_start [0:31];
    (* ramstyle = "MLAB, no_rw_check" *) logic [15:0] fet_loop  [0:31];
    always @(posedge m_clock) if (pwe) begin
        pram_cpu[pwaddr] <= pwdata; pram_eng[pwaddr] <= pwdata;
        if (pwaddr[2:0] == R_START) fet_start[pwaddr[7:3]] <= pwdata;
        if (pwaddr[2:0] == R_LOOP)  fet_loop[pwaddr[7:3]]  <= pwdata;
    end

    // Envelope readback (clamped EnvelopeVol, 15 bits) written by the engine.
    logic        env_we;
    logic [4:0]  env_wv;
    logic [14:0] env_wdata;
    (* ramstyle = "MLAB, no_rw_check" *) logic [14:0] env_rb [0:31];
    always @(posedge m_clock) if (env_we) env_rb[env_wv] <= env_wdata;

    // Voice flag vectors (several writers; later statements win).
    logic [NV-1:0] bnew, voice_off, isilent, restart, kon_pend, koff_pend;
    logic [7:0]    kon_stamp [NV], koff_stamp [NV];

    // CPU readback (RAM reads as continuous assignments)
    wire [14:0] env_rd = env_rb[cpu_v];
    wire [15:0] pc_rd  = pram_cpu[{cpu_v, cpu_r}];
    always @* begin
        io_Dout = 16'd0;
        if (io_get) begin
            if (a_mvl) io_Dout = main_volume_L;
            else if (a_mvr) io_Dout = main_volume_R;
            else if (a_ron0) io_Dout = rvb_on[15:0];
            else if (a_ron1) io_Dout = {8'd0, rvb_on[23:16]};
            else if (vpage && !io_A[0]) begin
                if (cpu_r == 3'd6) begin
                    if (bnew[cpu_v]) io_Dout = 16'd1;
                    else if (sw_spuenv_off || isilent[cpu_v]) io_Dout = 16'd0;
                    else io_Dout = {1'b0, env_rd};
                end else io_Dout = pc_rd;
            end
        end
    end

    // ------------------------------------------------------------------
    // Reverb: the unchanged sflc-generated module, as in the original DSP.
    // ------------------------------------------------------------------
    logic [20:0] main_L, main_R, rvb_add_L, rvb_add_R;
    logic [15:0] rvb_clip_L, rvb_clip_R;
    wire  [15:0] rvb_out_L, rvb_out_R;
    wire  [17:0] rvb_A;
    wire  [15:0] rvb_Dout;
    wire         rvb_read_req, rvb_write_req;
    logic [7:0]  doing, resume;
    always @* begin
        case (rvb_add_L[20:15])
            6'b111110: rvb_clip_L = 16'h8000;
            6'b000001: rvb_clip_L = 16'h7FFF;
            default:   rvb_clip_L = rvb_add_L[15:0];
        endcase
        case (rvb_add_R[20:15])
            6'b111110: rvb_clip_R = 16'h8000;
            6'b000001: rvb_clip_R = 16'h7FFF;
            default:   rvb_clip_R = rvb_add_R[15:0];
        endcase
    end
    reverb rvb (.p_reset(p_reset), .m_clock(m_clock),
        .io_set(io_set && a_rvbio), .io_A(io_A), .io_Din(io_Din), .run(rvb_run),
        .A(rvb_A), .Dout(rvb_Dout), .read_req(rvb_read_req), .write_req(rvb_write_req),
        .Din(vDin), .ack(ack && doing == 8'd24), .dma_doing(dma_doing),
        .SAMPLE_L(rvb_clip_L), .SAMPLE_R(rvb_clip_R), .out_L(rvb_out_L), .out_R(rvb_out_R));

    assign voice_out_L = sw_reverb_off ? main_L : main_L + (CtrlRvb ? {{5{rvb_out_L[15]}}, rvb_out_L} : 21'd0);
    assign voice_out_R = sw_reverb_off ? main_R : main_R + (CtrlRvb ? {{5{rvb_out_R[15]}}, rvb_out_R} : 21'd0);

    // ------------------------------------------------------------------
    // Initialisation sweep for the state RAMs after reset.
    // ------------------------------------------------------------------
    logic       init_busy;
    logic [4:0] init_v;
    always @(posedge m_clock) begin
        if (p_reset) begin init_busy <= 1'b1; init_v <= '0; end
        else if (init_busy) begin
            if (init_v == 5'd23) init_busy <= 1'b0;
            init_v <= init_v + 5'd1;
        end
    end

    // ------------------------------------------------------------------
    // Fetch unit: BRR block reads (dsp_ch src_read/read_wait), rotating 'doing'
    // slot 0..23 voices, 24 reverb, exactly like the original DSP.
    // ------------------------------------------------------------------
    localparam logic [1:0] F_IDLE = 2'd0, F_INIT = 2'd1, F_HEAD = 2'd2, F_DATA = 2'd3;
    typedef struct packed {
        logic [1:0]  st;
        logic [17:0] adrs;
        logic [2:0]  bk;
        logic        looping, f_loop, f_keep, f_copy;
        logic [2:0]  filter;
        logic [3:0]  shift;
    } fstate_t;
    localparam int FW = $bits(fstate_t);
    (* ramstyle = "MLAB, no_rw_check" *) logic [FW-1:0] fram [0:31];
    // Two-word prefetch ring per voice. Each word carries its block's
    // {silent_tag, filter, shift}; silent_tag marks the 7th word of an
    // end-without-keep block (dsp_ch sets iSilent when that word is requested).
    (* ramstyle = "MLAB, no_rw_check" *) logic [6:0]  hram [0:63];   // {filter, shift}
    logic [2*NV-1:0] tagv;                                            // silent tag per slot
    (* ramstyle = "MLAB, no_rw_check" *) logic [15:0] dram [0:63];
    logic        fwe, dwe;
    logic [4:0]  fwv;
    fstate_t     fwdata;
    logic [7:0]  hwdata;
    logic [15:0] dwdata;
    logic [NV-1:0] rp, wp;            // ring read/write slot
    logic [2*NV-1:0] cntv;            // words buffered per voice (0..2), 2 bits each
    always @(posedge m_clock) begin
        if (fwe) fram[fwv] <= fwdata;
        if (dwe) begin dram[{fwv, wp[fwv]}] <= dwdata; hram[{fwv, wp[fwv]}] <= hwdata[6:0]; end
        if (p_reset) tagv <= '0;
        else if (dwe) tagv[2*fwv + wp[fwv]] <= hwdata[7];
    end

    wire        dv      = doing < 8'd24;
    wire [4:0]  fv      = doing[4:0];
    fstate_t    fs;
    wire [FW-1:0] fram_rd = fram[fv];
    assign fs = fram_rd;
    wire [1:0]  cnt_fv = cntv[2*fv +: 2];
    wire [15:0] p_start = fet_start[fv];
    wire [15:0] p_loop  = fet_loop[fv];
    // Held request: latched in the first cycle, kept until ack.
    logic        hold;
    logic        hold_head;
    logic [17:0] hold_adrs;
    wire  [1:0]  eff_st   = restart[fv] ? F_INIT : fs.st;
    wire         eff_loop = restart[fv] ? 1'b0 : fs.looping;
    wire  [17:0] init_adrs = {(eff_loop ? p_loop[15:1] : p_start[15:1]), 3'b000};
    wire         want = dv && !init_busy && !restart[fv] && !voice_off[fv] && cnt_fv != 2'd2 &&
                        eff_st != F_IDLE;
    wire         new_head = eff_st != F_DATA;
    wire  [17:0] new_adrs = eff_st == F_INIT ? init_adrs : fs.adrs;
    wire         v_req = hold || want;

    always @* begin
        read_req = 1'b0; write_req = 1'b0;
        if (!ack) begin
            if (dv) read_req = v_req;
            else if (doing == 8'd24) begin read_req = rvb_read_req; write_req = rvb_write_req; end
        end
        vA    = dv ? (hold ? hold_adrs : new_adrs) : rvb_A;
        vDout = rvb_Dout;
    end

    // Fetch-side state RAM writes and flag effects (combinational intent, applied below).
    logic f_set_srcok, f_clr_restart;
    always @* begin
        fwe = 1'b0; dwe = 1'b0; fwv = fv; fwdata = fs; hwdata = '0; dwdata = vDin;
        fetch_lwe = 1'b0; fetch_lv = fv; fetch_ldata = '0;
        f_set_srcok = 1'b0; f_clr_restart = 1'b0;
        if (init_busy) begin
            fwe = 1'b1; fwv = init_v; fwdata = '0;
        end else if (dv && hold && ack) begin
            if (restart[fv] || voice_off[fv]) begin
                // stale read for a restarted/stopped voice: drop the data
            end else if (hold_head) begin
                fwe = 1'b1; fwdata.filter = vDin[6:4]; fwdata.shift = vDin[3:0];
                fwdata.st = F_DATA; fwdata.adrs = hold_adrs + 18'd1; fwdata.bk = 3'd1;
                fwdata.looping = 1'b0;
                fwdata.f_copy = vDin[10]; fwdata.f_keep = vDin[9]; fwdata.f_loop = vDin[8];
            end else begin
                dwe = 1'b1; f_set_srcok = 1'b1;
                hwdata = {fs.bk == 3'd7 && fs.f_loop && !fs.f_keep, fs.filter, fs.shift};
                fwe = 1'b1; fwdata.adrs = hold_adrs + 18'd1; fwdata.bk = fs.bk + 3'd1;
                if (fs.bk == 3'd7) begin
                    if (fs.f_copy) begin
                        fetch_lwe = 1'b1; fetch_ldata = {hold_adrs[17:3], 1'b0};
                    end
                    if (fs.f_loop) begin fwdata.looping = 1'b1; fwdata.st = F_INIT; end
                    else fwdata.st = F_HEAD;
                end
            end
        end else if (dv && !hold) begin
            if (restart[fv]) begin
                fwe = 1'b1; fwdata.st = F_INIT; fwdata.looping = 1'b0; f_clr_restart = 1'b1;
            end else if (voice_off[fv] && fs.st != F_IDLE) begin
                fwe = 1'b1; fwdata.st = F_IDLE;
            end
        end
    end

    always @(posedge m_clock) begin
        if (p_reset) begin doing <= '0; resume <= '0; hold <= 1'b0; hold_head <= 1'b0; hold_adrs <= '0; end
        else begin
            if (dv && !hold && want && !ack) begin
                hold <= 1'b1; hold_head <= new_head; hold_adrs <= new_adrs;
            end
            if (ack && dv) hold <= 1'b0;
            // Rotation as in the original DSP (0..23 voices, 24 reverb), except that a
            // pending reverb access is served next: voices have a two-word prefetch,
            // the reverb pass (one access per step) has a hard 22.05 kHz deadline.
            if (ack || (!read_req && !write_req)) begin
                if (doing == 8'd24) doing <= resume;
                else if (rvb_read_req || rvb_write_req || doing == 8'd23) begin
                    doing <= 8'd24; resume <= doing == 8'd23 ? 8'd0 : doing + 8'd1;
                end else doing <= doing + 8'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Engine: per-voice state and micro-sequenced datapath.
    // ------------------------------------------------------------------
    typedef struct packed {
        logic [14:0] pitch_count;
        logic        dec_pend;
        logic [1:0]  dec_rot;
        logic [15:0] pre0, pre1, decode_data;
        logic [7:0]  adsr_state;
        logic [15:0] env_vol;
        logic [23:0] env_vol_f;
        logic [15:0] out_L, out_R;
        logic        out_rvb;
        logic [7:0]  tick_done;
    } vstate_t;
    localparam int SW = $bits(vstate_t);
    (* ramstyle = "MLAB, no_rw_check" *) logic [SW-1:0] sram [0:31];
    logic    swe;
    logic [4:0] swv;
    vstate_t swdata;
    always @(posedge m_clock) if (swe) sram[swv] <= swdata;

    // Shared multipliers (signed 18x18, registered product).
    logic signed [17:0] ma0, mb0, ma1, mb1;
    logic signed [35:0] mp0, mp1;
    always @(posedge m_clock) begin mp0 <= ma0 * mb0; mp1 <= ma1 * mb1; end

    // ADSR rate ROMs (upstream Verilog, synchronous read).
    logic [6:0]  rom_add_a, rom_sub_a;
    wire  [13:0] rt_add;   wire [20:0] rt_add_f;
    wire  [14:0] rt_sub;   wire [21:0] rt_sub_f;
    RateTableAdd_rom   u_ra  (.m_clock(m_clock), .p_reset(p_reset), .adrs(rom_add_a), .dout(rt_add),   .read(1'b1));
    RateTableAdd_f_rom u_raf (.m_clock(m_clock), .p_reset(p_reset), .adrs(rom_add_a), .dout(rt_add_f), .read(1'b1));
    RateTableSub_rom   u_rs  (.m_clock(m_clock), .p_reset(p_reset), .adrs(rom_sub_a), .dout(rt_sub),   .read(1'b1));
    RateTableSub_f_rom u_rsf (.m_clock(m_clock), .p_reset(p_reset), .adrs(rom_sub_a), .dout(rt_sub_f), .read(1'b1));

    typedef enum logic [4:0] {
        E_IDLE, E_LOAD, E_STEP, E_PITCH, E_DEC1, E_DEC2, E_DEC3, E_ADSR_A, E_ADSR_B,
        E_ADSR_BW, E_ADSR_BW2, E_ADSR_C, E_ADSR_D, E_ADSR_E, E_OUT1, E_OUT2, E_OUT3, E_OUT4, E_OUT5,
        E_STORE
    } estate_t;
    estate_t es;
    logic [4:0]  cv;
    wire [SW-1:0] sram_rd = sram[cv];
    vstate_t     w;
    logic        env_tick;           // tick being processed is an envelope tick
    logic [15:0] ads, sr, voll, volr, pitch;
    logic        volume_pending, volume_apply;
    logic [23:0] cv_bit_q;

    // Derived ADSR inputs (ADSR.sflp port mapping from dsp_ch).
    wire        AttackModeExp  = ads[15];
    wire [6:0]  AttackRate     = ads[14:8];
    wire [3:0]  DecayRate      = ads[7:4];
    wire [3:0]  SustainLevel   = ads[3:0];
    wire        SustainModeExp = sr[15];
    wire        SustainIncrease = sr[14] == 1'b0;
    wire [6:0]  SustainRate    = sr[12:6];
    wire        ReleaseModeExp = sr[5];
    wire [4:0]  ReleaseRate    = sr[4:0];
    localparam logic [23:0] DENOM = 24'h200000;

    function automatic logic [17:0] sx18_16(input logic [15:0] x); sx18_16 = {{2{x[15]}}, x}; endfunction
    function automatic logic [20:0] sx21_16(input logic [15:0] x); sx21_16 = {{5{x[15]}}, x}; endfunction
    function automatic logic [14:0] env_clamp(input logic [15:0] v);
        case (v[15:14])
            2'b10:   env_clamp = 15'h7FFF;
            2'b11:   env_clamp = 15'h0000;
            default: env_clamp = v[14:0];
        endcase
    endfunction
    wire [14:0] cur_env = isilent[cv] ? 15'd0 : env_clamp(w.env_vol);
    logic [2:0] eng_preg;
    always @* case (es)
        E_LOAD:  eng_preg = R_PITCH;
        E_STEP:  eng_preg = R_ADS;
        E_PITCH: eng_preg = R_SR;
        E_OUT1:  eng_preg = R_VOLL;
        default: eng_preg = R_VOLR;
    endcase
    wire [15:0] pe_rd   = pram_eng[{cv, eng_preg}];
    wire [1:0]  cnt_cv  = cntv[2*cv +: 2];

    // BRR decode inputs
    wire [6:0]  hfs     = hram[{cv, rp[cv]}];
    wire [15:0] sdata   = dram[{cv, rp[cv]}];
    wire        hnext_tag = tagv[2*cv + {4'd0, ~rp[cv]}];
    wire [3:0]  nibble  = w.dec_rot == 2'd0 ? sdata[3:0] : w.dec_rot == 2'd1 ? sdata[7:4] :
                          w.dec_rot == 2'd2 ? sdata[11:8] : sdata[15:12];
    wire signed [15:0] now_data = $signed({nibble, 12'h000}) >>> hfs[3:0];
    logic signed [7:0] f0, f1;
    always @* case (hfs[6:4])
        3'd1: begin f0 = 8'sd60;  f1 = 8'sd0;   end
        3'd2: begin f0 = 8'sd115; f1 = -8'sd52; end
        3'd3: begin f0 = 8'sd98;  f1 = -8'sd55; end
        3'd4: begin f0 = 8'sd122; f1 = -8'sd60; end
        default: begin f0 = 8'sd0; f1 = 8'sd0; end
    endcase

    wire        owed       = w.tick_done != tick_cnt;
    wire        kon_due    = kon_pend[cv]  && kon_stamp[cv]  == w.tick_done;
    wire        koff_due   = koff_pend[cv] && koff_stamp[cv] == w.tick_done;
    wire [23:0] cv_bit     = 24'd1 << cv;

    // Engine-side flag effects for this cycle.
    logic e_clr_kon, e_clr_koff, e_clr_srcok, e_env_on, e_env_off, e_next_tag;
    logic [4:0] cv_q;

    always @(posedge m_clock) begin
        e_clr_kon <= 1'b0; e_clr_koff <= 1'b0; e_clr_srcok <= 1'b0; e_env_on <= 1'b0; e_env_off <= 1'b0;
        swe <= 1'b0; env_we <= 1'b0;
        if (p_reset) begin
            es <= E_IDLE; cv <= '0; volume_pending <= 1'b0; volume_apply <= 1'b0; env_tick <= 1'b0;
            main_L <= '0; main_R <= '0; rvb_add_L <= '0; rvb_add_R <= '0;
        end else if (init_busy) begin
            swe <= 1'b1; swv <= init_v; swdata <= '0;
            env_we <= 1'b1; env_wv <= init_v; env_wdata <= '0;
            es <= E_LOAD; cv <= '0;
        end else begin
            case (es)
            E_IDLE: es <= E_LOAD;
            E_LOAD: begin
                w <= sram_rd;
                pitch <= pe_rd;
                es <= E_STEP;
            end
            // Apply events and ticks for this voice in tick order.
            E_STEP: begin
                ads <= pe_rd;
                if (kon_due) begin
                    // dsp_ch key_on (the vector side effects happened at event time)
                    w.pitch_count <= '0; w.dec_pend <= 1'b0; w.dec_rot <= '0;
                    w.pre0 <= '0; w.pre1 <= '0; w.decode_data <= '0;
                    w.adsr_state <= 8'h10; w.env_vol <= '0; w.env_vol_f <= '0;
                    e_clr_kon <= 1'b1;
                end else if (koff_due) begin
                    if (cur_env != 15'd0) w.adsr_state <= 8'h40;
                    e_clr_koff <= 1'b1;
                end else if (owed) begin
                    es <= E_PITCH;
                end else es <= E_STORE;
            end
            E_PITCH: begin
                // pitch_run (176.4 kHz)
                logic [14:0] pitch_sa;
                pitch_sa = w.pitch_count - 15'h4000;
                if (pitch_sa[14]) w.pitch_count <= w.pitch_count + {1'b0, pitch[13:0]};
                else begin
                    w.dec_pend <= 1'b1;
                    w.pitch_count <= pitch_sa + {1'b0, pitch[13:0]};
                end
                env_tick <= w.tick_done[1:0] == 2'b11;
                w.tick_done <= w.tick_done + 8'd1;
                sr <= pe_rd;
                es <= E_DEC1;
            end
            E_DEC1: begin
                if (w.dec_pend && cnt_cv != 2'd0) begin
                    ma0 <= sx18_16(w.pre0); mb0 <= {{10{f0[7]}}, f0};
                    ma1 <= sx18_16(w.pre1); mb1 <= {{10{f1[7]}}, f1};
                    es <= E_DEC2;
                end else if (env_tick) es <= E_ADSR_A; else es <= E_STEP;
            end
            E_DEC2: es <= E_DEC3;  // products registered
            E_DEC3: begin
                logic signed [16:0] inner;
                logic [15:0] clip;
                inner = {now_data[15], now_data} + mp0[22:6] + mp1[22:6];
                case (inner[16:15])
                    2'b10: clip = 16'h8000;
                    2'b01: clip = 16'h7FFF;
                    default: clip = inner[15:0];
                endcase
                w.pre1 <= w.pre0; w.pre0 <= clip; w.decode_data <= clip;
                w.dec_rot <= w.dec_rot + 2'd1;
                w.dec_pend <= 1'b0;
                if (w.dec_rot == 2'd3) begin e_clr_srcok <= 1'b1; e_next_tag <= cnt_cv == 2'd2 && hnext_tag; end
                if (env_tick) es <= E_ADSR_A; else es <= E_STEP;
            end
            // ---- ADSR pass (ADSR.sflp adsr_stg), only when not silent ----
            E_ADSR_A: begin
                if (isilent[cv]) es <= E_OUT1;
                else begin
                    // states x0: select ROM addresses
                    case (w.adsr_state)
                        8'h10: begin
                            logic [15:0] dif; dif = 16'h6000 - w.env_vol;
                            rom_add_a <= (AttackModeExp && dif[15]) ? AttackRate + 7'd8 : AttackRate;
                            w.adsr_state <= 8'h11;
                        end
                        8'h20: begin rom_sub_a <= {1'b0, DecayRate, 2'b00}; w.adsr_state <= 8'h21; end
                        8'h30: begin
                            if (SustainIncrease) begin
                                logic [15:0] dif; dif = 16'h6000 - w.env_vol;
                                rom_add_a <= (SustainModeExp && dif[15]) ? SustainRate + 7'd8 : SustainRate;
                            end else rom_sub_a <= SustainRate;
                            w.adsr_state <= 8'h31;
                        end
                        8'h40: begin rom_sub_a <= {ReleaseRate, 2'b00}; w.adsr_state <= 8'h41; end
                        default: ;
                    endcase
                    if (w.adsr_state == 8'h10 || w.adsr_state == 8'h20 ||
                        w.adsr_state == 8'h30 || w.adsr_state == 8'h40) es <= E_ADSR_B;
                    else es <= E_OUT1;
                end
            end
            E_ADSR_B: es <= E_ADSR_BW;   // ROM address registered; output valid next cycle
            E_ADSR_BW: begin             // ROM outputs valid: exponential multiply operands
                ma0 <= {{3{rt_sub[14]}}, rt_sub}; mb0 <= {2'b00, w.env_vol};
                es <= E_ADSR_BW2;
            end
            E_ADSR_BW2: es <= E_ADSR_C;  // mp0 = sext(RateTableSub) * {0, env_vol}
            E_ADSR_C: begin  // states x1
                logic [15:0] expd; expd = mp0[30:15];
                case (w.adsr_state)
                    8'h11: begin
                        w.env_vol <= w.env_vol + {2'b00, rt_add};
                        w.env_vol_f <= w.env_vol_f + {3'b000, rt_add_f};
                        e_env_on <= 1'b1;
                        w.adsr_state <= 8'h12;
                    end
                    8'h21: begin
                        w.env_vol <= w.env_vol + expd;
                        w.env_vol_f <= w.env_vol_f + {{2{rt_sub_f[21]}}, rt_sub_f};
                        w.adsr_state <= 8'h22;
                    end
                    8'h31: begin
                        if (SustainIncrease) begin
                            w.env_vol <= w.env_vol + {2'b00, rt_add};
                            w.env_vol_f <= w.env_vol_f + {3'b000, rt_add_f};
                        end else begin
                            w.env_vol <= w.env_vol + (SustainModeExp ? expd : {rt_sub[14], rt_sub});
                            w.env_vol_f <= w.env_vol_f + {{2{rt_sub_f[21]}}, rt_sub_f};
                        end
                        w.adsr_state <= 8'h32;
                    end
                    8'h41: begin
                        w.env_vol <= w.env_vol + (ReleaseModeExp ? expd : {rt_sub[14], rt_sub});
                        w.env_vol_f <= w.env_vol_f + {{2{rt_sub_f[21]}}, rt_sub_f};
                        w.adsr_state <= 8'h42;
                    end
                    default: ;
                endcase
                es <= E_ADSR_D;
            end
            E_ADSR_D: begin  // states x2: fractional carry
                logic [23:0] ddif; logic denom_over;
                ddif = DENOM - w.env_vol_f; denom_over = ddif[23];
                case (w.adsr_state)
                    8'h12: if (denom_over) begin w.env_vol_f <= w.env_vol_f - DENOM; w.env_vol <= w.env_vol + 16'd1; end
                    8'h22, 8'h42: if (w.env_vol_f[23]) begin w.env_vol_f <= w.env_vol_f + DENOM; w.env_vol <= w.env_vol - 16'd1; end
                    8'h32: if (SustainIncrease) begin
                               if (denom_over) begin w.env_vol_f <= w.env_vol_f - DENOM; w.env_vol <= w.env_vol + 16'd1; end
                           end else if (w.env_vol_f[23]) begin w.env_vol_f <= w.env_vol_f + DENOM; w.env_vol <= w.env_vol - 16'd1; end
                    default: ;
                endcase
                w.adsr_state <= w.adsr_state + 8'd1;
                es <= E_ADSR_E;
            end
            E_ADSR_E: begin  // states x3 (and decay's 0x24)
                es <= E_OUT1;
                case (w.adsr_state)
                    8'h13: if (w.env_vol[15]) begin
                               w.env_vol <= 16'h7FFF; w.env_vol_f <= DENOM; w.adsr_state <= 8'h20;
                           end else w.adsr_state <= 8'h10;
                    8'h23: if (w.env_vol[15]) begin
                               w.env_vol <= '0; w.env_vol_f <= '0; w.adsr_state <= 8'h00; e_env_off <= 1'b1;
                           end else begin w.adsr_state <= 8'h24; es <= E_ADSR_E; end
                    8'h24: w.adsr_state <= w.env_vol[14:11] == SustainLevel ? 8'h30 : 8'h20;
                    8'h33: if (SustainIncrease) begin
                               if (w.env_vol[15]) begin w.env_vol <= 16'h7FFF; w.env_vol_f <= DENOM; w.adsr_state <= 8'h00; end
                               else w.adsr_state <= 8'h30;
                           end else begin
                               if (w.env_vol[15]) begin w.env_vol <= '0; w.env_vol_f <= '0; e_env_off <= 1'b1; w.adsr_state <= 8'h00; end
                               else w.adsr_state <= 8'h30;
                           end
                    8'h43: if (w.env_vol[15]) begin
                               w.env_vol <= '0; w.env_vol_f <= '0; e_env_off <= 1'b1; w.adsr_state <= 8'h00;
                           end else w.adsr_state <= 8'h40;
                    default: ;
                endcase
            end
            // ---- Output sample (44.1 kHz): interpolation, envelope, volume ----
            E_OUT1: begin
                logic [13:0] frac;
                frac = w.pitch_count[14] ? 14'h3FFF : w.pitch_count[13:0];
                begin logic [16:0] dif; dif = {w.pre0[15], w.pre0} - {w.pre1[15], w.pre1}; ma0 <= {dif[16], dif}; end
                mb0 <= {4'b0, frac};
                voll <= pe_rd;
                es <= E_OUT2;
            end
            E_OUT2: begin volr <= pe_rd; es <= E_OUT3; end
            E_OUT3: begin
                logic [15:0] interp;
                logic [9:0]  envelope;
                interp = w.pre1 + mp0[29:14];   // pre1 + ((pre0 - pre1) * frac) >>> 14
                envelope = sw_spuenv_off ? 10'd0 : cur_env[14:5];
                ma0 <= sx18_16(sw_intpl_off ? w.decode_data : interp);
                mb0 <= {8'b0, envelope};
                es <= E_OUT4;
            end
            E_OUT4: es <= E_OUT5;
            E_OUT5: begin
                // decenv = s16 * u10 >> 10 ; then volume (dsp_ch vol_mul)
                ma0 <= sx18_16(mp0[25:10]); mb0 <= {{3{voll[14]}}, voll[14:0]};
                ma1 <= sx18_16(mp0[25:10]); mb1 <= {{3{volr[14]}}, volr[14:0]};
                es <= E_STORE;
                w.out_rvb <= w.out_rvb;  // updated with the sums in E_STORE+
                env_tick <= 1'b0;
                volume_pending <= 1'b1;
            end
            E_STORE: begin
                if (volume_pending) begin
                    es <= E_STORE;     // wait one cycle for the volume products
                    volume_pending <= 1'b0;
                    volume_apply <= 1'b1;
                end else if (volume_apply) begin
                    logic [15:0] nl, nr;
                    nl = mp0[29:14]; nr = mp1[29:14];
                    main_L <= main_L + sx21_16(nl) - sx21_16(w.out_L);
                    main_R <= main_R + sx21_16(nr) - sx21_16(w.out_R);
                    rvb_add_L <= rvb_add_L + (rvb_on[cv] ? sx21_16(nl) : 21'd0)
                                           - (w.out_rvb ? sx21_16(w.out_L) : 21'd0);
                    rvb_add_R <= rvb_add_R + (rvb_on[cv] ? sx21_16(nr) : 21'd0)
                                           - (w.out_rvb ? sx21_16(w.out_R) : 21'd0);
                    w.out_L <= nl; w.out_R <= nr; w.out_rvb <= rvb_on[cv];
                    volume_apply <= 1'b0;
                    es <= E_STEP;      // more owed ticks/events for this voice?
                end else begin
                    swe <= 1'b1; swv <= cv; swdata <= w;
                    env_we <= 1'b1; env_wv <= cv; env_wdata <= env_clamp(w.env_vol);
                    cv <= cv == 5'd23 ? 5'd0 : cv + 5'd1;
                    es <= E_LOAD;
                end
            end
            default: es <= E_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Voice flag vectors: events (immediate effects), fetch and engine effects.
    // ------------------------------------------------------------------
    always @(posedge m_clock) begin
        if (p_reset) begin
            bnew <= '0; voice_off <= '0; isilent <= '0; restart <= '0;
            kon_pend <= '0; koff_pend <= '0; rp <= '0; wp <= '0; cntv <= '0;
        end else begin
            logic [NV-1:0] n_bnew, n_voff, n_sil, n_rst, n_kon, n_koff, n_rp, n_wp;
            logic [2*NV-1:0] n_cnt;
            n_bnew = bnew; n_voff = voice_off; n_sil = isilent;
            n_rst = restart; n_kon = kon_pend; n_koff = koff_pend; n_rp = rp; n_wp = wp;
            n_cnt = cntv;
            // Ring: fetch fills, engine consumes (both may hit the same voice).
            if (e_clr_srcok && n_cnt[2*cv_q +: 2] != 2'd0) begin   // a key_on may have flushed it
                n_cnt[2*cv_q +: 2] = n_cnt[2*cv_q +: 2] - 2'd1; n_rp[cv_q] = ~n_rp[cv_q];
                if (e_next_tag) n_sil[cv_q] = 1'b1;     // next word becomes current
            end
            if (f_set_srcok) begin
                // the filled word becomes current if the ring is (now) empty
                if (n_cnt[2*fv +: 2] == 2'd0 && hwdata[7]) n_sil[fv] = 1'b1;
                n_cnt[2*fv +: 2] = n_cnt[2*fv +: 2] + 2'd1; n_wp[fv] = ~n_wp[fv];
            end
            if (f_clr_restart) n_rst[fv] = 1'b0;
            if (e_clr_kon)     n_kon = n_kon & ~cv_bit_q;
            if (e_clr_koff)    n_koff = n_koff & ~cv_bit_q;
            // Envelope effects come from a tick processed before any still-pending
            // key_on of that voice; such a key_on happened later and wins.
            if (!sw_spuenv_off && ~|(kon_pend & cv_bit_q)) begin
                if (e_env_on)  n_bnew = n_bnew & ~cv_bit_q;
                if (e_env_off) begin n_bnew = n_bnew & ~cv_bit_q; n_voff = n_voff | cv_bit_q; end
            end
            for (int v = 0; v < NV; v++) begin
                if (kof_ev[v]) begin
                    n_bnew[v] = 1'b0;
                    if (!sw_spuenv_off) begin n_koff[v] = 1'b1; koff_stamp[v] <= tick_cnt; end
                end
                if (kon_ev[v]) begin
                    n_bnew[v] = 1'b1;
                    if (!sw_spuenv_off) begin
                        n_voff[v] = 1'b0; n_sil[v] = 1'b0; n_rst[v] = 1'b1;
                        n_cnt[2*v +: 2] = 2'd0; n_rp[v] = 1'b0; n_wp[v] = 1'b0;
                        n_kon[v] = 1'b1; kon_stamp[v] <= tick_cnt; n_koff[v] = 1'b0;
                    end
                end
            end
            bnew <= n_bnew; voice_off <= n_voff; isilent <= n_sil;
            restart <= n_rst; kon_pend <= n_kon; koff_pend <= n_koff; rp <= n_rp; wp <= n_wp;
            cntv <= n_cnt;
        end
    end
    // e_* strobes are registered one cycle after the engine decided them; use the
    // voice index that was current then.
    always @(posedge m_clock) begin cv_bit_q <= cv_bit; cv_q <= cv; end
endmodule
