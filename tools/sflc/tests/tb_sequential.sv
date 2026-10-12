`timescale 1ns/1ps
module tb_sequential;
  reg clk=0, reset=0;
  reg en=0,rd=0,wr=0,start=0,tick=0;
  reg [1:0] mode=0;
  reg [7:0] a=0;
  reg [2:0] addr=0;
  wire [7:0] value,memq,left,right,result;
  wire [3:0] set_value,initialized;
  wire busy,done;
  sequential dut(.m_clock(clk),.p_reset(reset),.en(en),.mode(mode),.a(a),.addr(addr),
    .rd(rd),.wr(wr),.start(start),.tick(tick),.value(value),.memq(memq),
    .left(left),.right(right),.busy(busy),.result(result),.done(done),
    .set_value(set_value),.initialized(initialized));
  reg [7:0] mem[0:7],r=0,l=0,rr=0,q;
  integer state=0; // independent transaction model: idle, capture, complete
  reg [7:0] data=0,res=0;
  reg [31:0] rng=32'hcade1984;
  integer checks=0;
  function automatic [31:0] next_random(input [31:0] v);
    v=v^(v<<13); v=v^(v>>17); v=v^(v<<5); next_random=v;
  endfunction
  task automatic edge_check;
    #2;
    if(done !== (state==2 && tick)) $fatal(1,"done not combinationally aligned to final state");
    if(start) begin
      if(state!=0) $fatal(1,"bad fixture start");
      state=1; data=a;
    end else if(state==1 && tick) begin res=data; state=2; end
    else if(state==2 && tick) begin res=res+1; state=0; end
    if(en) case(mode)
      0:r=r+1;
      1:r=a;
      2:r=r-1;
      3:r=r^a;
    endcase
    // Read-before-write on the same clock, using the old memory contents.
    if(rd) q=mem[addr];
    if(wr) mem[addr]=a;
    if(a[0]) l=l+1; else rr=rr+2;
    clk=1; #1;
    if(value!==r || memq!==q || busy!==(state!=0) || result!==res ||
       left!==l || right!==rr || set_value!==1 || initialized!==5)
       $fatal(1,"sequential mismatch check=%d r=%h/%h mem=%h/%h busy=%b state=%d result=%h/%h locals=%h/%h %h/%h",
         checks,value,r,memq,q,busy,state,result,res,left,l,right,rr);
    checks=checks+1;
    #2; clk=0;
  endtask
  task automatic async_reset;
    // Plain q and memory survive reset; resettable registers reset between edges.
    en=0;rd=0;wr=0;start=0;tick=0;
    #1; reset=1; #1;
    r=0;l=0;rr=0;state=0;data=0;res=0;
    if(value!==0 || busy!==0 || result!==0 || left!==0 || right!==0 ||
       set_value!==1 || initialized!==5 || memq!==q) $fatal(1,"async reset mismatch");
    reset=0; #1;
  endtask
  initial begin
    for(integer j=0;j<8;j=j+1) mem[j]=0;
    mem[0]=8'h10;mem[1]=8'h20;
    async_reset();
    for(integer i=0;i<4000;i=i+1) begin
      rng=next_random(rng);
      a=rng[7:0]; addr=rng[10:8];mode=rng[12:11];
      rd=rng[13];wr=rng[14];en=rng[15];tick=rng[16];
      start=(state==0)&&rng[17];
      edge_check();
      if(i%113==0) async_reset();
    end
    $display("PASS sequential cycles=%0d",checks);$finish;
  end
endmodule
