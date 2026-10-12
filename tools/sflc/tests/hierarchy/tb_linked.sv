`timescale 1ns/1ps
module tb_linked;
  reg clk=0,reset=0,push=0,take=0,which=0;
  reg [7:0] data=0;
  wire available,event_out;
  wire [7:0] value,mapped,local_value;
  linked d(.m_clock(clk),.p_reset(reset),.push(push),.take(take),.which(which),.data(data),
    .available(available),.value(value),.mapped(mapped),.local_value(local_value),.ready_event(event_out));
  reg [7:0] contents[0:1];
  reg valid[0:1];
  reg [31:0] rng=32'hcac47d12;
  reg [7:0] expected;
  integer checks=0;
  task automatic check_outputs;
    #1;
    expected=valid[which]?contents[which]:8'b0;
    if(available!==valid[which] || event_out!==valid[which] || value!==expected)
      $fatal(1,"child response routing mismatch checks=%d",checks);
    if(mapped!==(push?(data^8'h5a):8'b0) || local_value!==(push?8'(data+3):8'b0))
      $fatal(1,"guarded call result mismatch");
    // When the result is inactive the child must not be spuriously invoked.
    if(d.transform.con!==push) $fatal(1,"call side effect escaped its guard");
  endtask
  initial begin
    valid[0]=0;valid[1]=0;contents[0]=0;contents[1]=0;
    #1;reset=1;#1;reset=0;
    for(integer i=0;i<2000;i=i+1) begin
      rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
      data=rng[7:0];which=rng[8];push=rng[9];take=!push&&rng[10];
      check_outputs();
      if(push) begin contents[which]=data;valid[which]=1;end
      if(take) valid[which]=0;
      clk=1;check_outputs();clk=0;checks=checks+1;
      if(i%79==0) begin
        push=0;take=0;reset=1;valid[0]=0;valid[1]=0;contents[0]=0;contents[1]=0;
        check_outputs();reset=0;
      end
    end
    $display("PASS linked cycles=%0d",checks);$finish;
  end
endmodule
