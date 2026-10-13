`timescale 1ns/1ps
module tb_join_reductions;
    reg clk=0;
    reg reset=0;
    reg [3:0] bits=0;
    wire [3:0] ascending, descending, accumulated;
    integer i;
    join_reductions dut(.p_reset(reset), .m_clock(clk), .bits(bits),
                        .ascending(ascending), .descending(descending),
                        .accumulated(accumulated));

    task tick;
        begin #1 clk=1; #1 clk=0; #1; end
    endtask

    initial begin
        #1 reset=1;
        #1 reset=0;
        for (i=0;i<16;i=i+1) begin
            bits=i;
            #1;
            if (ascending !== {bits[0],bits[1],bits[2],bits[3]})
                $fatal(1,"ascending join bits=%b got=%b",bits,ascending);
            if (descending !== {bits[3],bits[2],bits[1],bits[0]})
                $fatal(1,"descending join bits=%b got=%b",bits,descending);
        end
        if (accumulated !== 0) $fatal(1,"unexpected initial accumulator %h",accumulated);
        tick();
        if (accumulated !== 6) $fatal(1,"first join reduction expected 6 got %h",accumulated);
        tick();
        if (accumulated !== 6) $fatal(1,"second join reduction expected 6 got %h",accumulated);
        $display("PASS join_reductions checks=34");
        $finish;
    end
endmodule
