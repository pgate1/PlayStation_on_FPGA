`timescale 1ns/1ps
// Independent per-word reference model of the guarded-OR bank semantics.
module tb_bank_ports;
  reg p_reset=1, m_clock=0;
  reg [7:0] a=0, b=0, c=0;
  reg [2:0] i1=0, i2=0, ix=0;
  reg clr=0, ws=0, wa=0, wb=0, wx=0, go=0;
  wire [7:0] q0, q1, q2, q3, q4, q5, q6, q7;
  wire busy, st;
  bank_ports dut(.p_reset(p_reset),.m_clock(m_clock),.a(a),.b(b),.c(c),.i1(i1),.i2(i2),.ix(ix),
    .clr(clr),.ws(ws),.wa(wa),.wb(wb),.wx(wx),.go(go),
    .q0(q0),.q1(q1),.q2(q2),.q3(q3),.q4(q4),.q5(q5),.q6(q6),.q7(q7),.busy(busy),.st(st));
  reg [7:0] ref_m [0:7];
  reg active=0, state=0;
  reg [31:0] rng=32'h13579bdf;
  integer checks=0, w, both=0;
  reg [7:0] data; reg en, s1_act, s2_act;
  wire [7:0] q [0:7];
  assign q[0]=q0; assign q[1]=q1; assign q[2]=q2; assign q[3]=q3;
  assign q[4]=q4; assign q[5]=q5; assign q[6]=q6; assign q[7]=q7;
  initial begin
    for(w=0;w<8;w=w+1) ref_m[w]=0;
    #5 m_clock=1; #5 m_clock=0; #5 m_clock=1; #5 m_clock=0; p_reset=0;
    for(integer cyc=0;cyc<3000;cyc=cyc+1) begin
      rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
      a=rng[7:0]; b=rng[15:8]; c=rng[23:16]; i1=rng[26:24]; i2=rng[29:27]; ix={rng[31:30],rng[0]};
      rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
      clr=(rng[3:0]==0); ws=rng[4]&rng[5]; wa=rng[6]&rng[7]; wb=rng[8]&rng[9]; wx=rng[10]&rng[11]; go=(rng[14:12]==0);
      #1;
      if(busy!==active || (active && st!==state)) $fatal(1,"stage model busy=%0d active=%0d st=%0d state=%0d",busy,active,st,state);
      s1_act = active && state==0; s2_act = active && state==1;
      if(s1_act && (wa|wb|wx) && i2!=i1) both=both+1;
      for(w=0;w<8;w=w+1) begin
        data=0; en=0;
        if(clr) en=1;
        if(ws && w==3) begin en=1; data=data|a; end
        if(wa && i1==w) begin en=1; data=data|a; end
        if(wb && i1==w) begin en=1; data=data|b; end
        if(wx && i1==w) begin en=1; data=data|c; end
        if(s1_act && i2==w) begin en=1; data=data|c; end
        if(s2_act && ix==w) begin en=1; data=data|a; end
        if(en) ref_m[w]=data;
      end
      state = s1_act ? 1 : (s2_act ? 0 : state);
      active = go || (active && !s2_act);
      #4 m_clock=1; #5 m_clock=0;
      for(w=0;w<8;w=w+1) begin
        if(q[w]!==ref_m[w]) $fatal(1,"cycle %0d word %0d dut=%h ref=%h",cyc,w,q[w],ref_m[w]);
        checks=checks+1;
      end
    end
    if(both<20) $fatal(1,"too few simultaneous distinct-word writes: %0d",both);
    $display("PASS bank_ports checks=%0d parallel=%0d",checks,both);$finish;
  end
endmodule
