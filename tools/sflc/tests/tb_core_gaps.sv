`timescale 1ns/1ps
module tb_core_gaps;
  reg pick=0, go=0, hold=0;
  reg [7:0] a=0;
  wire [31:0] s;
  wire [7:0] first, req_a;
  wire req;
  core_gaps dut(.p_reset(1'b0),.m_clock(1'b0),.pick(pick),.a(a),.go(go),.hold(hold),
    .s(s),.first(first),.req_a(req_a),.req(req));
  reg [31:0] rng=32'h2468ace1;
  integer checks=0;
  initial begin
    for(integer i=0;i<1000;i=i+1) begin
      rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
      pick=rng[0];go=rng[1];hold=rng[2];a=rng[15:8];
      #1;
      // "FPGA"/"SCEI": first character in the most significant byte.
      if(s!==(pick?32'h46504741:32'h53434549) || first!==(pick?8'h46:8'h53))
        $fatal(1,"string constant pick=%0d s=%h first=%h",pick,s,first);
      // The empty call activates the terminal; only req(a) drives the formal.
      if(req!==(go|hold)) $fatal(1,"activation go=%0d hold=%0d req=%0d",go,hold,req);
      if(go && req_a!==a) $fatal(1,"argument go=%0d a=%h req_a=%h",go,a,req_a);
      checks=checks+1;
    end
    $display("PASS core_gaps checks=%0d",checks);$finish;
  end
endmodule
