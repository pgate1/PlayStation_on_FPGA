`timescale 1ns/1ps
// Standalone reverb equivalence: upstream reverb with its private buffer
// (module renamed reverb_buf) versus option O1 (work area in SPU RAM, module
// renamed reverb_sram), identical register writes, input samples and 22.05 kHz
// 'run' pulses. The SPU-RAM copy gets a memory model with random latency.
// After every pass both outputs must be equal.
module tb_reverb_equiv;
  parameter int PASSES = 400;
  parameter int MAXLAT = 40;
  reg clk = 0, reset = 1, run = 0, io_set = 0;
  reg [15:0] io_A = 0, io_Din = 0, sL = 0, sR = 0;
  wire [15:0] bL, bR, sLo, sRo, b_Dout, s_Dout;
  wire [17:0] b_A, s_A;
  wire b_rreq, b_wreq, s_rreq, s_wreq;
  reg  s_ack = 0; reg [15:0] s_Din = 0;
  reverb_buf  rb (.p_reset(reset), .m_clock(clk), .io_set(io_set), .io_A(io_A), .io_Din(io_Din), .run(run),
    .A(b_A), .Dout(b_Dout), .read_req(b_rreq), .write_req(b_wreq), .Din(16'd0), .ack(1'b0), .dma_doing(1'b0),
    .SAMPLE_L(sL), .SAMPLE_R(sR), .out_L(bL), .out_R(bR));
  reverb_sram rs (.p_reset(reset), .m_clock(clk), .io_set(io_set), .io_A(io_A), .io_Din(io_Din), .run(run),
    .A(s_A), .Dout(s_Dout), .read_req(s_rreq), .write_req(s_wreq), .Din(s_Din), .ack(s_ack), .dma_doing(1'b0),
    .SAMPLE_L(sL), .SAMPLE_R(sR), .out_L(sLo), .out_R(sRo));
  always #5 clk = ~clk;
  reg [31:0] rng = 32'hfeedc0de;
  function automatic [31:0] rnd(); begin rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5); rnd = rng; end endfunction
  reg [15:0] mem [0:262143];
  integer lat = -1, maxwait = 0, cur = 0; reg [17:0] adr; reg isw; reg [15:0] wd;
  always @(posedge clk) begin
    s_ack <= 0;
    if (lat < 0 && (s_rreq || s_wreq) && !s_ack) begin lat <= 2 + rnd() % (MAXLAT - 1); adr <= s_A; isw <= s_wreq; wd <= s_Dout; end
    else if (lat > 0) lat <= lat - 1;
    else if (lat == 0) begin s_ack <= 1; s_Din <= mem[adr]; if (isw) mem[adr] <= wd; lat <= -1; end
  end
  task automatic wr(input [15:0] a, input [15:0] d);
    begin @(negedge clk); io_A = a; io_Din = d; io_set = 1; @(negedge clk); io_set = 0; end
  endtask
  integer i, p, errors = 0, nonzero = 0, busy_max = 0, t0;
  initial begin
    for (i = 0; i < 262144; i++) mem[i] = 0;
    for (i = 0; i < 32768; i++) rb.buffer.cells[i] = 0;
    repeat (4) @(negedge clk); reset = 0;
    // The buffer build clears its private RAM for 32,768 cycles after reset
    // (upstream ram_clean); passes during that window corrupt its delay lines.
    repeat (33000) @(negedge clk);
    wr(16'h1DA2, 16'hE000);
    wr(16'h1D84, 16'h3FFF); wr(16'h1D86, 16'h3FFF);
    for (i = 16'h1DC0; i <= 16'h1DFE; i += 2) begin
      if (i >= 16'h1DD4 && i <= 16'h1DFA) wr(i, 1 + rnd() % 16);
      else if (i == 16'h1DC0 || i == 16'h1DC2) wr(i, 1 + rnd() % 8);
      else wr(i, rnd() & 16'h3FFF);
    end
    for (p = 0; p < PASSES; p++) begin
      sL = rnd(); sR = rnd();
      @(negedge clk); run = 1; @(negedge clk); run = 0;
      t0 = $time;
      repeat (2260) @(negedge clk);
      if (rs.f_run || rb.f_run) begin errors++; if (errors < 10) $display("LATE pass=%0d sram_f_run=%0d buf_f_run=%0d", p, rs.f_run, rb.f_run); end
      if (bL !== sLo || bR !== sRo) begin errors++; if (errors < 10) $display("DIFF pass=%0d buf=%h/%h sram=%h/%h", p, bL, bR, sLo, sRo); end
      if (bL != 0 || bR != 0) nonzero++;
    end
    $display("RESULT passes=%0d maxlat=%0d nonzero_outputs=%0d errors=%0d", PASSES, MAXLAT, nonzero, errors);
    if (errors || nonzero < PASSES / 4) $fatal(1, "FAIL"); else $display("PASS reverb_equiv");
    $finish;
  end
endmodule
