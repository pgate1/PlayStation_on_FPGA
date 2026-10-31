// SPDX-License-Identifier: MIT
// Self-checking bench for ram_320x240x15_dp. Reference model applies the same
// read-before-write rule. Run: see docs/POCKET_IMPLEMENTATION.md.
`timescale 1ns/1ps
module tb_ram_320x240x15_dp;
    localparam integer DEPTH = 320 * 240;
    localparam integer OPS = 200000;

    reg         clk = 0;
    always #5 clk = ~clk;

    reg         wr_en = 0;
    reg  [16:0] wr_adrs = 0;
    reg  [14:0] wr_data = 0;
    reg         rd_en = 0;
    reg  [16:0] rd_adrs = 0;
    wire [14:0] dout;

    ram_320x240x15_dp dut (
        .clk(clk), .wr_en(wr_en), .wr_adrs(wr_adrs), .wr_data(wr_data),
        .rd_en(rd_en), .rd_adrs(rd_adrs), .dout(dout)
    );

    reg [14:0] ref_mem [0:DEPTH-1];
    reg        exp_valid = 0;
    reg [14:0] exp_data = 0;
    integer    errors = 0;
    integer    checked = 0;
    integer    i;

    // Compare the output of the read issued in the previous cycle, then update the model.
    always @(posedge clk) begin
        if (exp_valid) begin
            checked <= checked + 1;
            if (dout !== exp_data) begin
                errors <= errors + 1;
                if (errors < 10)
                    $display("ERROR t=%0t dout=%h expected=%h", $time, dout, exp_data);
            end
        end
        exp_valid <= rd_en;
        if (rd_en)
            exp_data <= ref_mem[rd_adrs];
        if (wr_en)
            ref_mem[wr_adrs] <= wr_data;
    end

    // Stimulus: drive on negedge so setup is clean.
    integer seed = 1;
    integer op;
    reg [16:0] pick;
    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;

        // Fill the whole array so every location is defined in the model.
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk);
            wr_en = 1; wr_adrs = i; wr_data = i[14:0] ^ 15'h2A5A;
            rd_en = 0;
        end
        @(negedge clk);
        wr_en = 0;

        // Random mixed traffic. Some addresses are reused to force same-address collisions.
        for (op = 0; op < OPS; op = op + 1) begin
            @(negedge clk);
            pick = $urandom(seed) % DEPTH;
            wr_en = ($urandom % 3) != 0;
            rd_en = ($urandom % 4) != 0;
            wr_adrs = (($urandom % 8) == 0) ? rd_adrs : pick;
            rd_adrs = (($urandom % 2) == 0) ? pick : wr_adrs;
            wr_data = $urandom;
        end
        @(negedge clk);
        wr_en = 0; rd_en = 0;
        repeat (3) @(negedge clk);

        if (errors == 0)
            $display("PASS tb_ram_320x240x15_dp: %0d reads checked, %0d ops, 0 errors", checked, OPS);
        else
            $display("FAIL tb_ram_320x240x15_dp: %0d errors", errors);
        $finish;
    end
endmodule
