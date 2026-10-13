`timescale 1ns/1ps
// Reverb work-area placement check for spu_dsp_shared.
// Compile once with the internal-buffer reverb (upstream USE_BUF_RAM) and once
// with option O1 (work area in SPU RAM); identical stimulus. Reports whether
// every 22.05 kHz reverb pass starts before the next 'run' (no backlog), the
// busy fraction of the reverb, and logs every reverb output change to OUTFILE
// for comparison between the two builds.
module tb_reverb_mem;
  parameter int TICKS = 800;
  parameter int MAXLAT = 15;       // memory latency 2..MAXLAT cycles
  parameter int SEED = 32'h0badf00d;
  parameter string OUTFILE = "reverb_out.txt";
  reg clk = 0, reset = 1, run33 = 0;
  reg io_set = 0, io_get = 0;
  reg [15:0] io_A = 0, io_Din = 0;
  wire [15:0] io_Dout;
  wire rreq, wreq;
  wire [17:0] vA;
  wire [15:0] vDout;
  reg [15:0] vDin = 0;
  reg ack = 0;
  wire [20:0] outL, outR;
  wire [23:0] env;
  wire [7:0] halt;
  wire [31:0] dbg;
  spu_dsp_shared dut (.p_reset(reset), .m_clock(clk), .io_set(io_set), .io_A(io_A), .io_Din(io_Din),
    .io_get(io_get), .io_Dout(io_Dout), .CtrlRvb(1'b1), .CtrlIRQ(1'b0), .run33(run33),
    .read_req(rreq), .write_req(wreq), .vA(vA), .vDout(vDout), .vDin(vDin), .ack(ack),
    .dma_doing(1'b0), .sw_intpl_off(1'b0), .sw_reverb_off(1'b0), .sw_spuenv_off(1'b0),
    .voice_out_L(outL), .voice_out_R(outR), .disp_env(env), .halt_code(halt), .dbg(dbg));

  reg [31:0] rng = SEED;
  function automatic [31:0] rnd(); begin rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5); rnd = rng; end endfunction
  reg [31:0] lrng = 32'h13579bdf;  // separate stream for latency
  function automatic [31:0] lrnd(); begin lrng = lrng ^ (lrng << 13); lrng = lrng ^ (lrng >> 17); lrng = lrng ^ (lrng << 5); lrnd = lrng; end endfunction

  reg [15:0] mem [0:262143];
  integer lat = -1; reg [17:0] adr; reg isw; reg [15:0] wd;
  longint reads = 0, writes = 0;
  always @(posedge clk) begin
    ack <= 0;
    if (lat < 0 && (rreq || wreq) && !ack) begin lat <= 2 + lrnd() % (MAXLAT - 1); adr <= vA; isw <= wreq; wd <= vDout; end
    else if (lat > 0) lat <= lat - 1;
    else if (lat == 0) begin
      ack <= 1; vDin <= mem[adr];
      if (isw) begin mem[adr] <= wd; writes++; end else reads++;
      lat <= -1;
    end
  end

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

  // Reverb pass accounting.
  integer runs = 0, starts = 0, max_backlog = 0, busy = 0, total = 0, late = 0, done_passes = 0, maxin = 0, main_nz = 0;
  reg prev_active = 0;
  always @(posedge clk) if (!reset) begin
    total++;
    if (dut.rvb.__sfl_active_run_stg) busy++;
    if (dut.rvb_run) begin
      runs++;
      if (dut.rvb.f_run) late++;           // previous request not yet started
    end
    // a pass starts when the stage enters state 0 and ends in state 34 (RVBLeft update)
    if (dut.rvb.__sfl_active_run_stg && dut.rvb.__sfl_state_run_stg == 0 && !prev_active) starts++;
    if (dut.rvb.__sfl_active_run_stg && dut.rvb.__sfl_state_run_stg == 34) done_passes++;
    prev_active <= dut.rvb.__sfl_active_run_stg && dut.rvb.__sfl_state_run_stg == 0;
    if ($signed(dut.rvb_clip_L) > maxin || -$signed(dut.rvb_clip_L) > maxin) maxin = $signed(dut.rvb_clip_L) < 0 ? -$signed(dut.rvb_clip_L) : $signed(dut.rvb_clip_L);
    if ($signed(dut.main_L) != 0) main_nz++;
    if (runs - starts > max_backlog) max_backlog = runs - starts;
  end

`ifdef TRACE_RVB
  integer tr_n = 0;
  always @(posedge clk) if (!reset && dut.rvb.__sfl_active_run_stg && dut.rvb.__sfl_state_run_stg == 34 && tr_n < 12) begin
    tr_n++;
    $display("RVB pass t=%0d in=%h buf=%h iRVB=%h/%h RVB=%h/%h volL=%h start=%h curr=%h",
      $time, dut.rvb.INPUT_SAMPLE_L, dut.rvb.buf_data, dut.rvb.iRVBLeft, dut.rvb.iRVBRight,
      dut.rvb.RVBLeft, dut.rvb.RVBRight, dut.rvb.VolLeft, dut.rvb.StartAddr, dut.rvb.CurrAddr);
  end
`endif
  integer fd;
  reg [15:0] lastL = 0, lastR = 0;
  integer changes = 0;
  always @(posedge clk) if (!reset && (dut.rvb_out_L !== lastL || dut.rvb_out_R !== lastR)) begin
    lastL <= dut.rvb_out_L; lastR <= dut.rvb_out_R; changes++;
    $fdisplay(fd, "%h %h", dut.rvb_out_L, dut.rvb_out_R);
  end

  task automatic wr(input [15:0] a, input [15:0] d);
    begin @(negedge clk); io_A = a; io_Din = d; io_set = 1; @(negedge clk); io_set = 0; end
  endtask

  integer i, v, blk;
  reg [15:0] w;
  initial begin
    fd = $fopen(OUTFILE, "w");
    for (i = 0; i < 262144; i = i + 1) mem[i] = 0;
    for (blk = 0; blk < 2048; blk = blk + 1) begin
      w = rnd(); w[3:0] = rnd() % 13; w[6:4] = rnd() % 5; w[7] = 0; w[15:11] = 0;
      w[10:8] = (rnd() % 8 == 0) ? 3'b011 : 3'b000;
      mem[18'h1000 + blk*8] = w;
      for (i = 1; i < 8; i = i + 1) mem[18'h1000 + blk*8 + i] = rnd();
    end
`ifdef BUF_RAM
    // The private buffer powers up undefined; upstream clears it after reset
    // (ram_clean, 32K cycles). Start both builds from zeros.
    for (i = 0; i < 32768; i = i + 1) dut.rvb.buffer.cells[i] = 0;
`endif
    repeat (5) @(negedge clk); reset = 0;
    repeat (60) @(negedge clk);
    for (v = 0; v < 24; v = v + 1) begin
      wr(16'h1C00 + (v << 4), rnd() & 16'h1FFF);
      wr(16'h1C02 + (v << 4), rnd() & 16'h1FFF);
      wr(16'h1C04 + (v << 4), 16'h0400 + rnd() % 16'h3C00);
      wr(16'h1C06 + (v << 4), 16'h0400 + ((rnd() % 1900) << 1));
      wr(16'h1C08 + (v << 4), 16'h00FF);           // fast attack, slow decay
      wr(16'h1C0A + (v << 4), 16'h0000);
      wr(16'h1C0E + (v << 4), 16'h0400 + ((rnd() % 1900) << 1));
    end
    // Reverb: work area = last 32K halfwords (fits the private 32K buffer too).
    wr(16'h1DA2, 16'hE000);
    wr(16'h1D84, 16'h3FFF); wr(16'h1D86, 16'h3FFF);
    for (i = 16'h1DC0; i <= 16'h1DFE; i = i + 2) begin
      // offsets (APF/addresses) kept inside the area, volumes moderate
      // short delays (offset k returns after 4k passes) so echoes appear in the run
      if (i >= 16'h1DD4 && i <= 16'h1DFA) wr(i, 1 + rnd() % 16);
      else if (i == 16'h1DC0 || i == 16'h1DC2) wr(i, 1 + rnd() % 8);
      else wr(i, (rnd() & 16'h3FFF));
    end
    wr(16'h1D98, 16'hFFFF); wr(16'h1D9A, 16'h00FF);   // all voices to reverb
    wr(16'h1D88, 16'hFFFF); wr(16'h1D8A, 16'h00FF);   // key on all
    while (tick < TICKS) @(negedge clk);
    $fclose(fd);
    $display("RESULT maxlat=%0d ticks=%0d runs=%0d starts=%0d late_requests=%0d max_backlog=%0d passes_done=%0d max_rvb_input=%0d main_nonzero_cycles=%0d busy=%0.1f%% mem_reads=%0d mem_writes=%0d out_changes=%0d halt=%h",
             MAXLAT, TICKS, runs, starts, late, max_backlog, done_passes, maxin, main_nz, 100.0 * busy / total, reads, writes, changes, halt);
    $finish;
  end
endmodule
