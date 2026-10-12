`timescale 1ns/1ps
module tb_multi_task;
  reg clk=0, reset=0;
  reg start_a=0, start_b=0, stop=0;
  reg [7:0] a=0, b=0;
  wire busy_a, busy_b;
  wire [7:0] y;
  p21 dut(.p_reset(reset),.m_clock(clk),.start_a(start_a),.start_b(start_b),
    .stop(stop),.a(a),.b(b),.busy_a(busy_a),.busy_b(busy_b),.y(y));

  reg model_active=0, model_a=0, model_b=0;
  reg [7:0] model_arg=0, model_y=0;
  integer checks=0;

  task automatic check_outputs(input [255:0] where);
    begin
      if(busy_a !== model_a || busy_b !== model_b || y !== model_y)
        $fatal(1,"%0s expected busy=%b%b y=%h got busy=%b%b y=%h",
          where,model_a,model_b,model_y,busy_a,busy_b,y);
      checks=checks+1;
    end
  endtask

  // Model the source's edge ordering. r consumes the old active/task/argument
  // registers; starts capture their guarded-OR argument on this edge. A finish
  // clears old task bits, with a simultaneous start taking priority.
  task automatic tick(input bit sa,input bit sb,input bit st,
                      input [7:0] av,input [7:0] bv);
    reg next_active,next_a,next_b;
    reg [7:0] next_arg,next_y;
    reg finish_now, write_r;
    begin
      clk=0; start_a=sa; start_b=sb; stop=st; a=av; b=bv;
      #1; check_outputs("pre-edge");
      finish_now=model_active && st;
      next_active=sa || sb || (model_active && !finish_now);
      next_a=sa || (model_a && !finish_now);
      next_b=sb || (model_b && !finish_now);
      next_arg=model_arg;
      if(sa || sb) next_arg=(sa ? av : 8'h00) | (sb ? bv : 8'h00);
      next_y=model_y;
      write_r=model_active && (model_a || model_b);
      if(write_r)
        next_y=(model_a ? model_arg : 8'h00) |
               (model_b ? (model_arg+8'h01) : 8'h00);
      clk=1; #1;
      model_active=next_active; model_a=next_a; model_b=next_b;
      model_arg=next_arg; model_y=next_y;
      check_outputs("post-edge");
      clk=0; #1; check_outputs("post-fall");
    end
  endtask

  initial begin
    // Asynchronous reset must clear tasks, shared argument, and result without
    // waiting for a clock edge.
    #1; reset=1; #1; check_outputs("async reset");
    reset=0; #1; check_outputs("reset released");

    // A task remains active on idle edges. Starting task two while task one is
    // active overlaps them; the shared arg captures the new start's value.
    tick(1,0,0,8'h22,8'h00);
    tick(0,0,0,8'h00,8'h00); // r <= old arg (0x22)
    tick(0,1,0,8'h00,8'h40); // r uses old task one; arg captures 0x40
    tick(0,0,0,8'h00,8'h00); // both active: 0x40 | 0x41 = 0x41

    // Simultaneous starts combine the shared argument with guarded OR. With
    // both tasks active, r then combines arg and arg+1 on the following edge.
    tick(1,1,0,8'h12,8'h21); // arg = 0x12 | 0x21 = 0x33
    tick(0,0,0,8'h00,8'h00); // r = 0x33 | 0x34 = 0x37

    // Same-edge finish and generation: the old task runs for this edge, then
    // task two replaces task one and the stage stays active.
    tick(0,1,1,8'h00,8'h55);
    tick(0,0,0,8'h00,8'h00); // only task two runs, using captured 0x55
    tick(0,0,1,8'h00,8'h00); // finish clears task two and the active stage
    tick(0,0,0,8'h00,8'h00); // result holds after finish

    // Reassert both tasks, then asynchronously reset while they are active.
    tick(1,1,0,8'h0a,8'h05);
    #1; reset=1; #1;
    model_active=0; model_a=0; model_b=0; model_arg=0; model_y=0;
    check_outputs("async reset while active");
    reset=0; #1; check_outputs("active reset released");
    tick(0,0,0,8'h00,8'h00);

    $display("PASS multi-task checks=%0d",checks);
    $finish;
  end
  initial begin #100000; $fatal(1,"multi-task timeout"); end
endmodule
