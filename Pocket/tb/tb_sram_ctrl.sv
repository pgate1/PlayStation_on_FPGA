// SPDX-License-Identifier: MIT
// Self-checking bench for sram_ctrl with a behavioral 128K x 16 (256 KiB) async SRAM model.
// Checks read/write data against a reference array, one ack per command, and that
// the controller never drives the bus while the SRAM output is enabled.
// Run: see docs/POCKET_IMPLEMENTATION.md. +seed=<n>, +ops=<n> optional.
`timescale 1ns/1ps
module tb_sram_ctrl;
    localparam integer WORDS = 1 << 17;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;   // 50 MHz

    reg          rd_req = 0, wr_req = 0;
    reg  [16:0]  adrs = 0;
    reg  [15:0]  wdata = 0;
    wire         ack, busy;
    wire [15:0]  dout;

    wire         OEn, WEn, UBn, LBn, DEn;
    wire [16:0]  ADDR;
    wire [15:0]  Din;
    wire [15:0]  dq;

    sram_ctrl dut (
        .clk(clk), .rst(rst), .rd_req(rd_req), .wr_req(wr_req),
        .adrs(adrs), .wdata(wdata), .ack(ack), .dout(dout), .busy(busy),
        .OEn(OEn), .WEn(WEn), .UBn(UBn), .LBn(LBn), .DEn(DEn),
        .ADDR(ADDR), .Din(Din), .Dout(dq)
    );

    // ---- behavioral SRAM
    reg [15:0] mem [0:WORDS-1];
    assign dq = (!DEn)                 ? Din        : 16'hzzzz;
    assign dq = (!OEn && WEn)          ? mem[ADDR]  : 16'hzzzz;

    // Write on the rising edge of WEn (end of the write pulse); ADDR and Din are stable there.
    always @(posedge WEn)
        if (!DEn && !UBn && !LBn)
            mem[ADDR] <= Din;

    // ---- bus checks
    integer errors = 0;
    integer acks = 0;
    always @(posedge clk) begin
        if (!rst && !OEn && !DEn) begin
            errors = errors + 1;
            $display("ERROR t=%0t: OEn and DEn both asserted", $time);
        end
        if (ack) acks = acks + 1;
    end

    // ---- reference model and stimulus
    reg [15:0] ref_mem [0:WORDS-1];
    integer seed = 1, ops = 4000, n, timeout;
    reg [16:0] a;
    reg [15:0] d, q;
    integer    nops = 0;

    task automatic issue(input wr, input [16:0] addr, input [15:0] data, output [15:0] got);
        begin
            @(negedge clk);
            adrs = addr; wdata = data;
            wr_req = wr; rd_req = !wr;
            @(negedge clk);
            wr_req = 0; rd_req = 0;
            timeout = 0;
            while (!ack && timeout < 20) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!ack) begin
                errors = errors + 1;
                $display("ERROR t=%0t: no ack for op at %h", $time, addr);
            end
            got = dout;
            nops = nops + 1;
        end
    endtask

    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        if (!$value$plusargs("ops=%d", ops)) ops = 4000;

        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // Initialise both models to a known pattern.
        for (n = 0; n < WORDS; n = n + 1) begin
            mem[n] = 16'h0000;
            ref_mem[n] = 16'h0000;
        end

        for (n = 0; n < ops; n = n + 1) begin
            a = $urandom(seed) % WORDS;
            d = $urandom;
            if ($urandom % 2) begin
                issue(1, a, d, q);
                ref_mem[a] = d;
            end else begin
                issue(0, a, 16'h0, q);
                if (q !== ref_mem[a]) begin
                    errors = errors + 1;
                    if (errors < 10)
                        $display("ERROR t=%0t: read %h from %h, expected %h", $time, q, a, ref_mem[a]);
                end
            end
        end

        // Read-after-write to the same address, back to back.
        issue(1, 17'h1ABCD, 16'hBEEF, q);
        issue(0, 17'h1ABCD, 16'h0, q);
        if (q !== 16'hBEEF) begin
            errors = errors + 1;
            $display("ERROR: read-after-write got %h", q);
        end

        repeat (4) @(negedge clk);
        if (acks != nops)
            $display("NOTE: ack pulses %0d, commands %0d", acks, nops);
        if (errors == 0)
            $display("PASS tb_sram_ctrl: %0d commands, 0 errors", nops);
        else
            $display("FAIL tb_sram_ctrl: %0d errors", errors);
        $finish;
    end
endmodule
