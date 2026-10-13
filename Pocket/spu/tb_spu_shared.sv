`timescale 1ns/1ps
// Co-simulation: upstream DigitalSignalProcessor (24 x dsp_ch, sflc-generated)
// versus spu_dsp_shared, identical stimulus and SPU RAM contents.
// INTPL=0: per-voice outputs at every envelope tick and ADSR readback must match
// exactly. INTPL=1: report interpolation error statistics only.
module tb_spu_shared;
  parameter int INTPL = 0;
  parameter int TICKS = 1600;
  parameter int SEED  = 32'h1234abcd;
  reg clk = 0, reset = 1;
  reg run33 = 0;
  reg io_set = 0, io_get = 0;
  reg [15:0] io_A = 0, io_Din = 0;
  wire [15:0] r_io_Dout, n_io_Dout;
  wire r_rreq, r_wreq, n_rreq, n_wreq;
  wire [17:0] r_vA, n_vA;
  wire [15:0] r_vDout, n_vDout;
  reg  [15:0] r_vDin = 0, n_vDin = 0;
  reg  r_ack = 0, n_ack = 0;
  wire [20:0] r_outL, r_outR, n_outL, n_outR;
  wire [23:0] r_env, n_env;
  wire [7:0] r_halt, n_halt;
  wire [31:0] r_dbg, n_dbg;
  wire sw_intpl_off = (INTPL == 0);

  DigitalSignalProcessor ref_dsp (.p_reset(reset), .m_clock(clk), .io_set(io_set), .io_A(io_A), .io_Din(io_Din),
    .io_get(io_get), .io_Dout(r_io_Dout), .CtrlRvb(1'b0), .CtrlIRQ(1'b0), .run33(run33),
    .read_req(r_rreq), .write_req(r_wreq), .vA(r_vA), .vDout(r_vDout), .vDin(r_vDin), .ack(r_ack),
    .dma_doing(1'b0), .sw_intpl_off(sw_intpl_off), .sw_reverb_off(1'b1), .sw_spuenv_off(1'b0),
    .voice_out_L(r_outL), .voice_out_R(r_outR), .disp_env(r_env), .halt_code(r_halt), .dbg(r_dbg));
  spu_dsp_shared new_dsp (.p_reset(reset), .m_clock(clk), .io_set(io_set), .io_A(io_A), .io_Din(io_Din),
    .io_get(io_get), .io_Dout(n_io_Dout), .CtrlRvb(1'b0), .CtrlIRQ(1'b0), .run33(run33),
    .read_req(n_rreq), .write_req(n_wreq), .vA(n_vA), .vDout(n_vDout), .vDin(n_vDin), .ack(n_ack),
    .dma_doing(1'b0), .sw_intpl_off(sw_intpl_off), .sw_reverb_off(1'b1), .sw_spuenv_off(1'b0),
    .voice_out_L(n_outL), .voice_out_R(n_outR), .disp_env(n_env), .halt_code(n_halt), .dbg(n_dbg));

  wire [15:0] ref_L [24];
  wire [15:0] ref_R [24];
  assign ref_L[0] = ref_dsp.ch_00.voice_out_L; assign ref_R[0] = ref_dsp.ch_00.voice_out_R;
  assign ref_L[1] = ref_dsp.ch_01.voice_out_L; assign ref_R[1] = ref_dsp.ch_01.voice_out_R;
  assign ref_L[2] = ref_dsp.ch_02.voice_out_L; assign ref_R[2] = ref_dsp.ch_02.voice_out_R;
  assign ref_L[3] = ref_dsp.ch_03.voice_out_L; assign ref_R[3] = ref_dsp.ch_03.voice_out_R;
  assign ref_L[4] = ref_dsp.ch_04.voice_out_L; assign ref_R[4] = ref_dsp.ch_04.voice_out_R;
  assign ref_L[5] = ref_dsp.ch_05.voice_out_L; assign ref_R[5] = ref_dsp.ch_05.voice_out_R;
  assign ref_L[6] = ref_dsp.ch_06.voice_out_L; assign ref_R[6] = ref_dsp.ch_06.voice_out_R;
  assign ref_L[7] = ref_dsp.ch_07.voice_out_L; assign ref_R[7] = ref_dsp.ch_07.voice_out_R;
  assign ref_L[8] = ref_dsp.ch_08.voice_out_L; assign ref_R[8] = ref_dsp.ch_08.voice_out_R;
  assign ref_L[9] = ref_dsp.ch_09.voice_out_L; assign ref_R[9] = ref_dsp.ch_09.voice_out_R;
  assign ref_L[10] = ref_dsp.ch_0A.voice_out_L; assign ref_R[10] = ref_dsp.ch_0A.voice_out_R;
  assign ref_L[11] = ref_dsp.ch_0B.voice_out_L; assign ref_R[11] = ref_dsp.ch_0B.voice_out_R;
  assign ref_L[12] = ref_dsp.ch_0C.voice_out_L; assign ref_R[12] = ref_dsp.ch_0C.voice_out_R;
  assign ref_L[13] = ref_dsp.ch_0D.voice_out_L; assign ref_R[13] = ref_dsp.ch_0D.voice_out_R;
  assign ref_L[14] = ref_dsp.ch_0E.voice_out_L; assign ref_R[14] = ref_dsp.ch_0E.voice_out_R;
  assign ref_L[15] = ref_dsp.ch_0F.voice_out_L; assign ref_R[15] = ref_dsp.ch_0F.voice_out_R;
  assign ref_L[16] = ref_dsp.ch_10.voice_out_L; assign ref_R[16] = ref_dsp.ch_10.voice_out_R;
  assign ref_L[17] = ref_dsp.ch_11.voice_out_L; assign ref_R[17] = ref_dsp.ch_11.voice_out_R;
  assign ref_L[18] = ref_dsp.ch_12.voice_out_L; assign ref_R[18] = ref_dsp.ch_12.voice_out_R;
  assign ref_L[19] = ref_dsp.ch_13.voice_out_L; assign ref_R[19] = ref_dsp.ch_13.voice_out_R;
  assign ref_L[20] = ref_dsp.ch_14.voice_out_L; assign ref_R[20] = ref_dsp.ch_14.voice_out_R;
  assign ref_L[21] = ref_dsp.ch_15.voice_out_L; assign ref_R[21] = ref_dsp.ch_15.voice_out_R;
  assign ref_L[22] = ref_dsp.ch_16.voice_out_L; assign ref_R[22] = ref_dsp.ch_16.voice_out_R;
  assign ref_L[23] = ref_dsp.ch_17.voice_out_L; assign ref_R[23] = ref_dsp.ch_17.voice_out_R;

  // ---------------- RNG ----------------
  reg [31:0] rng = SEED;
  function automatic [31:0] rnd(); begin rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5); rnd = rng; end endfunction

  // ---------------- SPU RAM (one copy per DUT) ----------------
  reg [15:0] mem_r [0:262143];
  reg [15:0] mem_n [0:262143];
  // Memory port model in the style of SoundProcessingUnit: accept a held
  // request when idle, ack after a random latency with the read data.
  integer r_lat = -1, n_lat = -1;
  reg [17:0] r_adr, n_adr;
  reg r_isw, n_isw;
  reg [15:0] r_wd, n_wd;
  always @(posedge clk) begin
    r_ack <= 0; n_ack <= 0;
    if (r_lat < 0 && (r_rreq || r_wreq) && !r_ack) begin r_lat <= 2 + rnd() % 14; r_adr <= r_vA; r_isw <= r_wreq; r_wd <= r_vDout; end
    else if (r_lat > 0) r_lat <= r_lat - 1;
    else if (r_lat == 0) begin r_ack <= 1; r_vDin <= mem_r[r_adr]; if (r_isw) mem_r[r_adr] <= r_wd; r_lat <= -1; end
    if (n_lat < 0 && (n_rreq || n_wreq) && !n_ack) begin n_lat <= 2 + rnd() % 14; n_adr <= n_vA; n_isw <= n_wreq; n_wd <= n_vDout; end
    else if (n_lat > 0) n_lat <= n_lat - 1;
    else if (n_lat == 0) begin n_ack <= 1; n_vDin <= mem_n[n_adr]; if (n_isw) mem_n[n_adr] <= n_wd; n_lat <= -1; end
  end

  // ---------------- clock, run33 DDS, tick counter ----------------
  always #5 clk = ~clk;
  longint acc = 0;
  integer dc = 1, tick = 0;
  always @(posedge clk) begin
    if (reset) begin run33 <= 0; acc <= 0; dc <= 1; tick <= 0; end
    else begin
      if (acc + 33868800 >= 50000000) begin acc <= acc + 33868800 - 50000000; run33 <= 1; end
      else begin acc <= acc + 33868800; run33 <= 0; end
      if (run33) begin if (dc == 192) begin dc <= 1; tick <= tick + 1; end else dc <= dc + 1; end
    end
  end

  // ---------------- capture of new engine outputs per (voice, tick) ----------------
  reg [15:0] mine_L [0:23][0:4095];
  reg [15:0] mine_R [0:23][0:4095];
  reg        mine_v [0:23][0:4095];
  // The engine's tick counters are 8 bits; rebuild the full index from tb 'tick'.
  integer mi;
  always @(posedge clk) if (!reset && new_dsp.es == new_dsp.E_STORE && new_dsp.volume_apply) begin
    mi = tick - ((tick - (new_dsp.w.tick_done - 1)) & 255);
    mine_L[new_dsp.cv][mi] <= new_dsp.mp0[29:14];
    mine_R[new_dsp.cv][mi] <= new_dsp.mp1[29:14];
    mine_v[new_dsp.cv][mi] <= 1;
  end


`ifdef TRACE
  integer tv = `TRACE;
  reg [15:0] last_ref_dec = 0;
  always @(posedge clk) if (!reset) begin
    if (new_dsp.es == new_dsp.E_DEC3 && new_dsp.cv == tv)
      $display("NEW dec tick=%0d rot=%0d clip=%h hfs=%h sdata=%h", new_dsp.w.tick_done - 1, new_dsp.w.dec_rot, new_dsp.w.pre0, new_dsp.hfs, new_dsp.sdata);
    if (new_dsp.dv && new_dsp.fv == tv && new_dsp.hold && new_dsp.ack)
      $display("NEW ack t=%0d tick=%0d head=%0d adrs=%h din=%h bk=%0d", $time, tick, new_dsp.hold_head, new_dsp.hold_adrs, n_vDin, new_dsp.fs.bk);
    if (ref_dsp.ch_00.__sfl_active_read_wait && ref_dsp.ch_00.read_ack && tv == 0)
      $display("REF ack t=%0d tick=%0d rid=%0d adrs=%h din=%h", $time, tick, ref_dsp.ch_00.rid_reg, ref_dsp.ch_00.vA_reg, ref_dsp.ch_00.vDin);
    if (ref_dsp.ch_00.decode_data != last_ref_dec && tv == 0) begin
      $display("REF dec tick=%0d clip=%h", tick, ref_dsp.ch_00.decode_data); last_ref_dec <= ref_dsp.ch_00.decode_data; end
  end
`endif
  // Engine progress: last tick each voice has fully processed (for parameter
  // writes, which the shared engine samples when it visits a voice).
  reg [7:0] done_tick [0:23];
  always @(posedge clk) if (!reset && new_dsp.swe && !new_dsp.init_busy) done_tick[new_dsp.swv] <= new_dsp.swdata.tick_done;
  function automatic bit engine_caught_up();
    engine_caught_up = 1;
    for (int k = 0; k < 24; k++) if (done_tick[k] !== new_dsp.tick_cnt) engine_caught_up = 0;
  endfunction
  // ---------------- bus tasks ----------------
  task automatic wr(input [15:0] a, input [15:0] d);
    begin @(negedge clk); io_A = a; io_Din = d; io_set = 1;
`ifdef TRACE_WR
      if (tick > 8) $display("WR t=%0d tick=%0d dc=%0d a=%h d=%h", $time, tick, dc, a, d);
`endif
      @(negedge clk); io_set = 0; end
  endtask
  integer errors = 0, checks = 0, env_checks = 0;
  task automatic check_env();
    integer v;
    begin
      for (v = 0; v < 24; v = v + 1) begin
        @(negedge clk); io_A = 16'h1C0C + (v << 4); io_get = 1; #1;
        if (r_io_Dout !== n_io_Dout) begin
          errors = errors + 1;
          if (errors < 20) $display("ENV MISMATCH tick=%0d v=%0d ref=%h new=%h", tick, v, r_io_Dout, n_io_Dout);
        end
        env_checks = env_checks + 1;
        @(negedge clk); io_get = 0;
      end
    end
  endtask

  // ---------------- stimulus ----------------

  integer i, v, blk, t, last_tick;
  reg [15:0] w;
  reg [15:0] rl [0:23][0:4095];
  reg [15:0] rr [0:23][0:4095];
  reg        rv [0:23][0:4095];
  real se = 0, sn = 0; longint maxe = 0;
  // Independent sampler: reference outputs 100 cycles after each envelope tick.
  initial begin : sampler
    integer st, sv;
    forever begin
      @(posedge clk);
      if (!reset && run33 && dc == 192 && (tick + 1) % 4 == 0) begin
        st = tick;            // envelope tick index processed now (0-based)
        repeat (100) @(negedge clk);
        for (sv = 0; sv < 24; sv = sv + 1) begin rl[sv][st] = ref_L[sv]; rr[sv][st] = ref_R[sv]; rv[sv][st] = 1; end
      end
    end
  end
  initial begin
    // BRR data: 2048 blocks of 8 halfwords from address 0x1000 (halfwords).
    for (i = 0; i < 262144; i = i + 1) begin mem_r[i] = 0; mem_n[i] = 0; end
    for (blk = 0; blk < 2048; blk = blk + 1) begin
      w = rnd();
      w[3:0] = rnd() % 13; w[6:4] = rnd() % 5; w[7] = 0;
      w[15:11] = 0; w[10:8] = (rnd() % 8 == 0) ? 3'b011 : ((rnd() % 4 == 0) ? 3'b100 : 3'b000);
      mem_r[18'h1000 + blk*8] = w; mem_n[18'h1000 + blk*8] = w;
      for (i = 1; i < 8; i = i + 1) begin w = rnd(); mem_r[18'h1000 + blk*8 + i] = w; mem_n[18'h1000 + blk*8 + i] = w; end
    end
    repeat (5) @(negedge clk); reset = 0;
    repeat (60) @(negedge clk);
    for (v = 0; v < 24; v = v + 1) begin
      wr(16'h1C00 + (v << 4), rnd() & 16'h7FFF);
      wr(16'h1C02 + (v << 4), rnd() & 16'h7FFF);
      wr(16'h1C04 + (v << 4), 16'h0400 + rnd() % 16'h3C00);
      wr(16'h1C06 + (v << 4), 16'h0400 + ((rnd() % 1900) << 1));   // 8-byte units, block aligned
      wr(16'h1C08 + (v << 4), rnd());
      wr(16'h1C0A + (v << 4), rnd());
      wr(16'h1C0E + (v << 4), 16'h0400 + ((rnd() % 1900) << 1));
    end
    wr(16'h1D88, 16'hFFFF); wr(16'h1D8A, 16'h00FF);
    last_tick = tick;
    while (tick < TICKS) begin
      @(negedge clk);
      if (tick != last_tick) begin
        last_tick = tick;
        if (tick % 4 == 2) check_env();
        // Occasional parameter changes and key events, kept away from tick edges.
        if (tick % 4 == 1 && rnd() % 6 == 0) begin
          v = rnd() % 24;
          i = rnd() % 5;
          // Parameter writes wait until the engine has processed every tick so far
          // (documented sampling delay of up to ~2 ticks); key events are exact.
          if (i >= 2) while (!engine_caught_up() && tick % 4 == 1) @(negedge clk);
          if (tick % 4 == 1 || i < 2)
          case (i)
            0: wr(16'h1D8C + ((v >= 16) ? 2 : 0), 16'h1 << (v % 16));
            1: wr(16'h1D88 + ((v >= 16) ? 2 : 0), 16'h1 << (v % 16));
            2: wr(16'h1C04 + (v << 4), 16'h0200 + rnd() % 16'h3E00);
            3: wr(16'h1C00 + (v << 4), rnd() & 16'h7FFF);
            4: wr(16'h1C0A + (v << 4), rnd());
          endcase
        end
      end
    end
    repeat (3000) @(negedge clk);
    for (t = 3; t < TICKS - 4; t = t + 4)
      for (v = 0; v < 24; v = v + 1)
        if (rv[v][t] && mine_v[v][t]) begin
          longint e;
          checks = checks + 1;
          e = $signed(rl[v][t]) - $signed(mine_L[v][t]); if (e < 0) e = -e; if (e > maxe) maxe = e; se = se + e * e;
          e = $signed(rr[v][t]) - $signed(mine_R[v][t]); if (e < 0) e = -e; if (e > maxe) maxe = e; se = se + e * e;
          sn = sn + 1.0 * $signed(rl[v][t]) * $signed(rl[v][t]);
          if (INTPL == 0 && (rl[v][t] !== mine_L[v][t] || rr[v][t] !== mine_R[v][t])) begin
            errors = errors + 1;
            if (errors < 2000) $display("OUT MISMATCH tick=%0d v=%0d ref=%h/%h new=%h/%h", t, v, rl[v][t], rr[v][t], mine_L[v][t], mine_R[v][t]);
          end
        end
    if (r_halt !== 0 || n_halt !== 0) begin errors = errors + 1; $display("HALT ref=%h new=%h", r_halt, n_halt); end
    $display("RESULT intpl=%0d ticks=%0d out_checks=%0d env_checks=%0d errors=%0d max_abs_err=%0d rms_err=%0.2f",
             INTPL, TICKS, checks, env_checks, errors, maxe, checks ? $sqrt(se / (2.0 * checks)) : 0.0);
    if (INTPL == 0 && (errors != 0 || checks < 1000)) $fatal(1, "FAIL");
    $display(INTPL == 0 ? "PASS spu_shared exact" : "DONE spu_shared interpolation stats");
    $finish;
  end
endmodule
