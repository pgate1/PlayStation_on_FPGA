// SPDX-License-Identifier: MIT
// drawPoly clut-cache check: build this with sflc --hierarchy drawPoly.sflp from a prepared dir with and without
// the clut-cache option plus the mul_*.v/compare_s11.v leaves; the +trace files must be identical (13602 pixels;
// the patched one needs about 26 % fewer clocks and 60 % fewer CLUT reads in the mock).
`timescale 1ns/1ps
// drawPoly trace test: random textured triangles; writes every emitted pixel to +trace=FILE.
// The CLUT-cache build must give the same trace as the unpatched drawPoly (VRAM unchanged between commands).
module tb_poly;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  reg [10:0] px1,py1,px2,py2,px3,py3;
  reg [23:0] pc1,pc2,pc3;
  reg [7:0] pu1,pv1,pu2,pv2,pu3,pv3;
  reg [15:0] clut; reg [13:0] tpage;
  reg draw = 0;
  wire drawing, view_on;
  wire [9:0] view_x; wire [8:0] view_y;
  wire [7:0] out_R, out_G, out_B;
  wire [18:0] vram_adrs; wire [15:0] vram_write_data; wire vram_write_req, vram_read_req, vram_flush_req;
  reg vram_ack = 0; reg [15:0] vram_read_data = 0;
  wire tcache_read; wire [18:0] tcache_adrs;
  reg [15:0] tcache_dout = 0; reg tcache_ack = 1;

  drawPoly dut(.p_reset(rst), .m_clock(clk), .px1(px1), .py1(py1), .pc1(pc1), .pu1(pu1), .pv1(pv1),
    .px2(px2), .py2(py2), .pc2(pc2), .pu2(pu2), .pv2(pv2), .px3(px3), .py3(py3), .pc3(pc3), .pu3(pu3), .pv3(pv3),
    .clut(clut), .tpage(tpage), .drawX(10'd0), .drawY(10'd0), .drawW(10'd1023), .drawH(10'd1023), .con(1'b0),
    .draw(draw), .drawing(drawing), .f_dither(1'b0), .f_texture(1'b1), .f_texblend(1'b0), .f_semitrans(1'b0),
    .sw_outview_on(1'b0), .sw_view_half_width(1'b0), .sw_view_half_height(1'b0),
    .view_x(view_x), .view_y(view_y), .view_on(view_on), .out_R(out_R), .out_G(out_G), .out_B(out_B),
    .vram_adrs(vram_adrs), .vram_write_data(vram_write_data), .vram_write_req(vram_write_req),
    .vram_read_req(vram_read_req), .vram_ack(vram_ack), .vram_read_data(vram_read_data), .vram_flush_req(vram_flush_req),
    .tcache_read(tcache_read), .tcache_adrs(tcache_adrs), .tcache_dout(tcache_dout), .tcache_ack(tcache_ack),
    .dbg_in(16'd0));

  reg [15:0] vram [0:524287];
  reg [31:0] cs = 32'h1234567, ls = 32'h9abcdef;
  function [31:0] rc(input integer n);
    begin cs = cs * 32'd1664525 + 32'd1013904223; rc = (cs >> 8) % n; end
  endfunction
  function [31:0] rl(input integer n);
    begin ls = ls * 32'd1103515245 + 32'd12345; rl = (ls >> 10) % n; end
  endfunction

  integer tc_cnt = 0; reg [18:0] tcache_adrs_q;
  always @(posedge clk) begin
    if (tcache_read) begin
      tcache_adrs_q <= tcache_adrs;
      tc_cnt = rl(4);
      tcache_ack <= (tc_cnt == 0);
      tcache_dout <= (tc_cnt == 0) ? vram[tcache_adrs] : 16'hDEAD;
    end else if (tc_cnt > 0) begin
      tc_cnt = tc_cnt - 1;
      if (tc_cnt == 0) begin tcache_ack <= 1; tcache_dout <= vram[tcache_adrs_q]; end
    end
  end

  reg busy = 0; integer lat = 0; reg [18:0] radr; integer nread = 0, nwrite = 0;
  reg wpend = 0;
  always @(posedge clk) begin
    vram_ack <= 0; vram_read_data <= 16'hBEEF;
    if (!busy) begin
      if (vram_read_req && !vram_ack) begin busy = 1; lat = 3 + rl(10); radr = vram_adrs; nread = nread + 1; end
      else if (vram_write_req && !vram_ack) begin busy = 1; lat = 2; radr = 19'h7ffff; nwrite = nwrite + 1; end
    end else begin
      lat = lat - 1;
      if (lat <= 0) begin vram_ack <= 1; vram_read_data <= vram[radr]; busy = 0; end
    end
  end

  integer f, npix = 0;
  always @(posedge clk) if (view_on) begin
    $fwrite(f, "%0d %0d %02x %02x %02x\n", view_x, view_y, out_R, out_G, out_B);
    npix = npix + 1;
  end

  integer i, k, t; reg [15:0] cl [0:5]; reg [13:0] tp [0:5];
  string fn;
  initial begin
    if (!$value$plusargs("trace=%s", fn)) fn = "trace.txt";
    f = $fopen(fn, "w");
    for (i = 0; i < 524288; i = i + 1) vram[i] = rc(65536);
    for (i = 0; i < 6; i = i + 1) begin
      cl[i] = {1'b0, rc(480) + 8'd0, 6'd0} | rc(60);
      tp[i] = {5'b0, rc(3), 2'b0, rc(2), rc(16)};
      tp[i][8:7] = i % 3;
    end
    repeat (4) @(posedge clk); rst = 0; repeat (4) @(posedge clk);
    for (t = 0; t < 150; t = t + 1) begin
      k = rc(6); clut = cl[k]; tpage = tp[k];
      px1 = 2 + rc(200); py1 = 2 + rc(120); px2 = px1 + rc(30); py2 = py1 + 2 + rc(20); px3 = px1 + rc(30); py3 = py1 + 2 + rc(20);
      pc1 = {rc(256), rc(256), rc(256)}; pc2 = pc1; pc3 = pc1;
      pu1 = rc(256); pv1 = rc(256); pu2 = rc(256); pv2 = rc(256); pu3 = rc(256); pv3 = rc(256);
      @(posedge clk); draw = 1; @(posedge clk); draw = 0;
      begin : w1 integer g; g = 0; while (!drawing && g < 8) begin @(posedge clk); g = g + 1; end end
      begin : w2 integer g; g = 0; while (drawing && g < 400000) begin @(posedge clk); g = g + 1; if (g == 400000) $display("TIMEOUT cmd %0d", t); end end
      repeat (2 + rl(4)) @(posedge clk);
    end
    $display("RESULT poly: pixels=%0d clut_reads=%0d writes=%0d time=%0t", npix, nread, nwrite, $time);
    $fclose(f);
    $finish;
  end
endmodule
