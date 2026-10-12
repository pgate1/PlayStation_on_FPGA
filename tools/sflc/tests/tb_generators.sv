`timescale 1ns/1ps
module tb_generators;
  reg clk=0, reset=0;
  reg load=0, wr=0;
  reg [1:0] addr=0;
  reg [7:0] a=0;
  reg [3:0] bits=0;
  wire [7:0] q0,q1,q2,q3,local_count;
  wire [2:0] first;
  wire [3:0] mask;
  p27 dut(.p_reset(reset),.m_clock(clk),.load(load),.wr(wr),.addr(addr),
    .a(a),.bits(bits),.q0(q0),.q1(q1),.q2(q2),.q3(q3),
    .first(first),.mask(mask),.local_count(local_count));

  reg [7:0] model_mem[0:3];
  reg [7:0] model_count[0:3];
  reg [7:0] want_local;
  reg [2:0] want_first;
  reg [3:0] want_mask;
  reg found;
  integer checks=0;
  integer i;
  reg [31:0] rng=32'h8f31a5c7;

  // All task calls are sequential and nonrecursive. Static task storage also
  // avoids Icarus 11's automatic-task/unpacked-array output propagation issue:
  // the original bench saw X outputs despite initialized DUT memory words.
  task check_outputs(input [8*24-1:0] where);
    begin
      want_mask=bits;
      want_first=3'd7; found=0;
      for(integer j=0;j<4;j=j+1) begin
        if(!found && bits[j]) begin want_first=j; found=1; end
      end
      want_local=model_count[addr];
      if(q0!==model_mem[0] || q1!==model_mem[1] ||
         q2!==model_mem[2] || q3!==model_mem[3] ||
         first!==want_first || mask!==want_mask || local_count!==want_local)
        $fatal(1,"%0s mem=%h %h %h %h expected=%h %h %h %h first=%0d/%0d mask=%h/%h count=%h/%h addr=%0d bits=%h",
          where,q0,q1,q2,q3,model_mem[0],model_mem[1],model_mem[2],model_mem[3],
          first,want_first,mask,want_mask,local_count,want_local,addr,bits);
      checks=checks+1;
    end
  endtask

  task tick(input bit do_load,input bit do_wr,
                      input [1:0] wr_addr,input [7:0] data,
                      input [3:0] active_bits);
    reg [7:0] old_mem[0:3];
    reg [7:0] next_mem[0:3];
    reg [7:0] next_count[0:3];
    begin
      clk=0; load=do_load; wr=do_wr; addr=wr_addr; a=data; bits=active_bits;
      #1; check_outputs("pre-edge");
      for(integer j=0;j<4;j=j+1) begin
        old_mem[j]=model_mem[j]; next_mem[j]=model_mem[j];
        next_count[j]=model_count[j] + (active_bits[j] ? 8'd1 : 8'd0);
        if(do_load) next_mem[j]=data+j;
        if(do_wr && wr_addr==j) begin
          if(do_load) next_mem[j]=(data+j)|data;
          else next_mem[j]=data;
        end
      end
      clk=1; #1;
      for(integer j=0;j<4;j=j+1) begin
        model_mem[j]=next_mem[j]; model_count[j]=next_count[j];
      end
      check_outputs("post-edge");
      clk=0; #1; check_outputs("post-fall");
    end
  endtask

  task async_reset_counters;
    begin
      clk=0; reset=1; #1;
      for(integer j=0;j<4;j=j+1) model_count[j]=0;
      check_outputs("async reset");
      reset=0; #1; check_outputs("reset released; memory retained");
    end
  endtask

  initial begin
    // Memory initialization is one-time; register counters reset asynchronously.
    #1; reset=1; #1;
    for(i=0;i<4;i=i+1) begin model_mem[i]=0; model_count[i]=0; end
    check_outputs("initial asynchronous reset");
    reset=0; #1; check_outputs("initial reset released");

    // All four constant-address writes must land on one rising edge.
    tick(1,0,0,8'h20,0);
    if(q0!==8'h20 || q1!==8'h21 || q2!==8'h22 || q3!==8'h23)
      $fatal(1,"parallel load did not initialize four distinct words");

    // A selected write after load changes only its addressed word.
    tick(0,1,3,8'h77,0);
    if(q3!==8'h77 || q0!==8'h20 || q1!==8'h21 || q2!==8'h22)
      $fatal(1,"selected write changed an unintended word");

    // At the overlapping address the two guarded writers combine by OR.
    tick(1,1,1,8'h0f,0);
    if(q1!==(8'h10|8'h0f)) $fatal(1,"load/write overlap did not OR same-address data");

    // Exhaust every bit mask. Counters are distinct per unrolled iteration.
    for(i=0;i<16;i=i+1) tick(0,0,i[1:0],0,i[3:0]);
    async_reset_counters();
    if(q0!==8'h0f || q1!==8'h1f || q2!==8'h11 || q3!==8'h12)
      $fatal(1,"asynchronous reset did not retain initialized memory contents");

    // Deterministic LCG, with unconstrained load/write overlap and all addresses.
    for(i=0;i<2000;i=i+1) begin
      rng=rng*32'd1664525+32'd1013904223;
      tick(rng[0],rng[1],rng[3:2],rng[15:8],rng[23:20]);
      if(i==499 || i==1249) async_reset_counters();
    end

    $display("PASS generators checks=%0d cycles=2019",checks);
    $finish;
  end
  initial begin #1000000; $fatal(1,"generator timeout"); end
endmodule
