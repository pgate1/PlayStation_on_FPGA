// SPDX-License-Identifier: MIT
// Unit test of drawRect with the clut-cache option (Pocket/source_fixes/pocket_top_fixes.json O-CLUT-R*):
// 400 random textured sprites (4/8/15-bit, 6 CLUTs, random mock latencies) against an independently
// computed pixel list. +rewrite=1 rewrites CLUT contents between commands: the unpatched drawRect fails
// that (stale one-entry CLUT register), the patched one must not. Prints RESULT ... errors=0.
// Run: sflc --hierarchy drawRect.sflp (in a prepared ps1/sfl dir, with/without the option) > drawRect.sv, then
//   verilator --binary --timing --top-module tb_rect -Wno-fatal tb_rect_clut.sv drawRect.sv compare_s11.v
//   ./obj_dir/Vtb_rect +rewrite=1
`timescale 1ns/1ps
// drawRect unit test: textured sprites against an independent expected pixel list.
// +rewrite=1 rewrites CLUT contents between commands (stale-CLUT check; the unpatched drawRect fails it)
module tb_rect;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [10:0] vx1, vy1, vx4, vy4;
  reg [23:0] col = 0;
  reg [15:0] clut;
  reg [13:0] tpage;
  reg [7:0] vu1, vv1, vu4 = 0, vv4 = 0;
  reg draw = 0;
  wire drawing, view_on;
  wire [9:0] view_x; wire [8:0] view_y;
  wire [7:0] out_R, out_G, out_B;
  wire [18:0] vram_adrs; wire vram_read_req;
  reg vram_ack = 0; reg [15:0] vram_read_data = 0;
  wire tcache_read; wire [18:0] tcache_adrs;
  reg [15:0] tcache_dout = 0; reg tcache_ack = 1;

  drawRect dut(.p_reset(rst), .m_clock(clk), .vx1(vx1), .vy1(vy1), .vx4(vx4), .vy4(vy4), .col(col),
    .clut(clut), .tpage(tpage), .vu1(vu1), .vv1(vv1), .vu4(vu4), .vv4(vv4),
    .drawX(10'd0), .drawY(10'd0), .drawW(10'd1023), .drawH(10'd1023), .con(1'b0),
    .sw_view_half_width(1'b0), .sw_view_half_height(1'b0), .draw(draw), .drawing(drawing),
    .f_texture(1'b1), .f_texblend(1'b0), .f_semitrans(1'b0),
    .view_x(view_x), .view_y(view_y), .view_on(view_on), .out_R(out_R), .out_G(out_G), .out_B(out_B),
    .vram_adrs(vram_adrs), .vram_read_req(vram_read_req), .vram_ack(vram_ack), .vram_read_data(vram_read_data),
    .tcache_read(tcache_read), .tcache_adrs(tcache_adrs), .tcache_dout(tcache_dout), .tcache_ack(tcache_ack));

  reg [15:0] vram [0:524287];
  reg [31:0] cs = 32'h1234567, ls = 32'h9abcdef;
  function [31:0] rc(input integer n);  // content random in [0,n)
    begin cs = cs * 32'd1664525 + 32'd1013904223; rc = (cs >> 8) % n; end
  endfunction
  function [31:0] rl(input integer n);  // latency random in [0,n)
    begin ls = ls * 32'd1103515245 + 32'd12345; rl = (ls >> 10) % n; end
  endfunction

  // tcache model: ack low for 0..3 cycles after a read; dout valid only while ack
  integer tc_cnt = 0;
  always @(posedge clk) begin
    if (tcache_read) begin
      tcache_dout <= vram[tcache_adrs];
      tc_cnt = rl(4);
      tcache_ack <= (tc_cnt == 0);
      if (tc_cnt != 0) tcache_dout <= 16'hDEAD;
      if (tc_cnt != 0) tc_cnt = tc_cnt;
    end else if (tc_cnt > 0) begin
      tc_cnt = tc_cnt - 1;
      if (tc_cnt == 0) begin tcache_ack <= 1; tcache_dout <= vram[tcache_adrs_q]; end
    end
  end
  reg [18:0] tcache_adrs_q;
  always @(posedge clk) if (tcache_read) tcache_adrs_q <= tcache_adrs;

  // single-word VRAM read model (CLUT), ack pulse after 3..12 cycles
  reg busy = 0; integer lat = 0; reg [18:0] radr; integer nread = 0;
  always @(posedge clk) begin
    vram_ack <= 0; vram_read_data <= 16'hBEEF;
    if (!busy) begin
      if (vram_read_req && !vram_ack) begin busy = 1; lat = 3 + rl(10); radr = vram_adrs; nread = nread + 1; end
    end else begin
      lat = lat - 1;
      if (lat <= 0) begin vram_ack <= 1; vram_read_data <= vram[radr]; busy = 0; end
    end
  end

  // expected pixels: {x[9:0], y[8:0], w[14:0]}
  reg [33:0] expq [$];
  integer errors = 0, checked = 0;
  reg [33:0] e;
  always @(posedge clk) if (view_on) begin
    if (expq.size() == 0) begin errors = errors + 1; if (errors < 10) $display("extra pixel %0d,%0d", view_x, view_y); end
    else begin
      e = expq.pop_front();
      checked = checked + 1;
      if (e[33:15] != {view_x, view_y} || e[14:0] != {out_B[7:3], out_G[7:3], out_R[7:3]}) begin
        errors = errors + 1;
        if (errors < 10) $display("MISMATCH exp x=%0d y=%0d c=%h  got x=%0d y=%0d R%h G%h B%h", e[33:24], e[23:15], e[14:0], view_x, view_y, out_R, out_G, out_B);
      end
    end
  end

  function [15:0] texel(input [10:0] x, input [10:0] y);
    reg [7:0] u, v; reg [18:0] base, a; reg [15:0] w; reg [7:0] idx; reg [18:0] cp, tadj; reg [1:0] mode;
    begin
      u = vu1 + (x - vx1); v = vv1 + (y - vy1);
      mode = tpage[8:7];
      tadj = {tpage[4], 8'b0, tpage[3:0], 6'b0}; // (tbase_y || tbase_x)
      cp = {clut[14:6], clut[5:0], 4'b0};
      a = {1'b0, v, 10'b0} + tadj;
      case (mode)
        0: begin w = vram[a + (u >> 2)]; idx = (w >> {u[1:0], 2'b00}) & 8'h0F; w = vram[cp + idx]; end
        1: begin w = vram[a + (u >> 1)]; idx = (w >> {u[0], 3'b000}) & 8'hFF; w = vram[cp + idx]; end
        default: w = vram[a + u];
      endcase
      texel = w;
    end
  endfunction

  task expect_cmd;
    integer xx, yy; reg [15:0] w;
    begin
      for (yy = vy1; yy < vy4; yy = yy + 1)
        for (xx = vx1; xx < vx4; xx = xx + 1) begin
          w = texel(xx, yy);
          if ((w[14:0] != 0) || (w == 16'h8000))
            expq.push_back({xx[9:0], yy[8:0], w[14:0]});
        end
    end
  endtask

  integer i, k, t;
  reg [15:0] cl [0:5]; reg [13:0] tp [0:5];
  integer rewrite;
  initial begin
    if (!$value$plusargs("rewrite=%d", rewrite)) rewrite = 0;
    for (i = 0; i < 524288; i = i + 1) vram[i] = rc(65536);
    for (i = 0; i < 6; i = i + 1) begin
      cl[i] = {1'b0, rc(480) + 8'd0, 6'd0} | rc(60); // varied clut origins
      tp[i] = {5'b0, rc(3), 2'b0, rc(2), rc(16)};
      tp[i][8:7] = i % 3;
    end
    repeat (4) @(posedge clk); rst = 0; repeat (4) @(posedge clk);
    for (t = 0; t < 400; t = t + 1) begin
      k = rc(6); clut = cl[k]; tpage = tp[k];
      if (rewrite && rc(3) == 0) for (i = 0; i < 256; i = i + 1) vram[{clut[14:6], clut[5:0], 4'b0} + i] = rc(65536);
      vx1 = 1 + rc(200); vy1 = 1 + rc(100); vx4 = vx1 + 2 + rc(24); vy4 = vy1 + 2 + rc(16);
      vu1 = rc(256); vv1 = rc(256);
      expect_cmd;
      @(posedge clk); draw = 1; @(posedge clk); draw = 0;
      begin : w1 integer g; g = 0; while (!drawing && g < 5) begin @(posedge clk); g = g + 1; end end
      begin : w2 integer g; g = 0; while (drawing && g < 200000) begin @(posedge clk); g = g + 1; if (g == 200000) begin $display("TIMEOUT cmd %0d", t); errors = errors + 1; end end end
      repeat (2 + rl(4)) @(posedge clk);
      if (expq.size() != 0) begin errors = errors + 1; if (errors < 10) $display("cmd %0d: %0d pixels missing", t, expq.size()); expq.delete(); end
    end
    $display("RESULT %s: checked=%0d errors=%0d clut_sdram_reads=%0d cycles=%0t", rewrite ? "rewrite" : "static", checked, errors, nread, $time/10);
    $finish;
  end
endmodule
