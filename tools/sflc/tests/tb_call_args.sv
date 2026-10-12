`timescale 1ns/1ps
module tb_call_args;
  reg [7:0] a=0,b=0,c=0;
  reg one=0,left_start=0,right_start=0,direct_start=0;
  wire [7:0] single_value,many_value,direct_value,forward_value;
  wire req;
  wire [7:0] shared_value,same_value,mixed_value;
  wire [7:0] plain,selected,repeated,mixture,direct_only;
  wire bit_data,bit_constant,event_out;
  wire [7:0] wide_constant,nested,duplicate,combined;
  p23 argument_cases(.p_reset(1'b0),.m_clock(1'b0),.a(a),.b(b),.c(c),
    .start_one(one),.start_left(left_start),.start_right(right_start),
    .start_direct(direct_start),.one_value(single_value),.many_value(many_value),
    .direct_value(direct_value));
  p18 forwarding(.p_reset(1'b0),.m_clock(1'b0),.a(a),.go(one),.o(forward_value),.req(req));
  p24 shared_cases(.p_reset(1'b0),.m_clock(1'b0),.a(a),.b(b),.first(one),
    .second(left_start),.third(right_start),.shared_value(shared_value),
    .same_value(same_value),.mixed_value(mixed_value));
  p25 selectors(.p_reset(1'b0),.m_clock(1'b0),.a(a),.b(b),.c(c),.first(one),
    .second(left_start),.third(right_start),.plain(plain),.selected(selected),
    .repeated(repeated),.mixture(mixture),.direct_only(direct_only));
  p26 data_controls(.p_reset(1'b0),.m_clock(1'b0),.a(a),.b(b),.c(one),
    .s(left_start),.bit_input(direct_start),.bit_data(bit_data),.bit_constant(bit_constant),
    .wide_constant(wide_constant),.nested(nested),.duplicate(duplicate),
    .combined(combined),.event_out(event_out));
  reg [7:0] expected_many;
  integer checks=0;
  initial begin
    // Exercise inactive controls and every overlap, including nonzero data
    // while all controls are low. Expectations established by native p18/p23.
    for(integer data=0;data<256;data=data+1) begin
      a=data;b=data^8'h96;c={a[3:0],a[7:4]};
      for(integer controls=0;controls<16;controls=controls+1) begin
        {one,left_start,right_start,direct_start}=controls;
        expected_many=(left_start?b:8'b0)|(right_start?c:8'b0);
        #1;
        if(single_value!==a || many_value!==expected_many || direct_value!==(a|c) ||
           forward_value!==a || req!==one)
          $fatal(1,"control argument mismatch data=%h controls=%h",a,controls);
        if(shared_value!==((one?a:8'b0)|(left_start?b:8'b0)) || same_value!==a ||
           mixed_value!==((one?a:8'b0)|(right_start?b:8'b0)))
          $fatal(1,"shared argument mismatch data=%h controls=%h",a,controls);
        if(plain!==a || selected!==a || repeated!==a || mixture!==(a|b|c) || direct_only!==c ||
           bit_data!==direct_start || bit_constant!==one || event_out!==one ||
           wide_constant!==8'h34 || nested!==(one?(left_start?a:b):8'b0) ||
           duplicate!==a || combined!==(a|b))
          $fatal(1,"data selector mismatch data=%h controls=%h",a,controls);
        checks=checks+1;
      end
    end
    $display("PASS call arguments checks=%0d",checks);$finish;
  end
endmodule
