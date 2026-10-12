`timescale 1ns/1ps
module tb_instance_arrays;
  reg [4:0] pick=0;
  reg [7:0] d=0;
  reg [1:0] t_pick=0;
  wire [7:0] y,z;
  arr dut(.p_reset(1'b0),.m_clock(1'b0),.pick(pick),.d(d),.t_pick(t_pick),.y(y),.z(z));
  reg [18:0] cons;
  reg [3:0] tcons;
  reg [7:0] want_y,want_z;
  reg [31:0] rng=32'h51ed270b;
  integer checks=0;
  task check;
    begin
      #1;
      cons={dut.slot_11.con,dut.slot_10.con,dut.slot_0F.con,dut.slot_0E.con,
            dut.slot_0D.con,dut.slot_0C.con,dut.slot_0B.con,dut.slot_0A.con,
            dut.slot_09.con,dut.slot_08.con,dut.slot_07.con,dut.slot_06.con,
            dut.slot_05.con,dut.slot_04.con,dut.slot_03.con,dut.slot_02.con,
            dut.slot_01.con,dut.slot_00.con};
      tcons={dut.t_3.con,dut.t_2.con,dut.t_1.con,dut.t_0.con};
      want_y=(pick<18) ? (8'(d+pick) ^ 8'h5a) : 8'h00;
      want_z=(d ^ {6'b0,t_pick}) ^ 8'h5a;
      if(y!==want_y || z!==want_z)
        $fatal(1,"data mismatch pick=%0d d=%h y=%h/%h t_pick=%0d z=%h/%h",
               pick,d,y,want_y,t_pick,z,want_z);
      // Each element is invoked only when selected; none otherwise.
      if(cons!==((pick<18) ? (19'b1<<pick) : 19'b0))
        $fatal(1,"slot call routing mismatch pick=%0d cons=%b",pick,cons);
      if(tcons!==(4'b1<<t_pick))
        $fatal(1,"t call routing mismatch t_pick=%0d tcons=%b",t_pick,tcons);
      checks=checks+1;
    end
  endtask
  initial begin
    for(integer i=0;i<4000;i=i+1) begin
      rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
      pick=rng[4:0];d=rng[15:8];t_pick=rng[17:16];
      check();
    end
    // Exhaustive over every selector value with a fixed datum.
    for(integer p=0;p<32;p=p+1) begin pick=p;d=8'ha7;t_pick=p[1:0];check();end
    $display("PASS instance_arrays checks=%0d",checks);$finish;
  end
endmodule
