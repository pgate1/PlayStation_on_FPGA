// SPDX-License-Identifier: MIT
// Self-checking bench for sdram128_burstn_wordside (Pocket/rtl/sdram128_burstn_adapter.sv)
// against a behavioural in-order word controller with the MIRLO sdr_ctrl request/
// response interface (random backpressure, random read latency, tags) and a
// halfword reference model. The command driver behaves like Pocket/core.sflp:
// it registers ack once and issues one-cycle strobes only while that copy is 1.
// Run:
//   iverilog -g2012 -s tb_sdram128_burstn_adapter -o tb.vvp \
//     Pocket/rtl/sdram128_burstn_adapter.sv Pocket/tb/tb_sdram128_burstn_adapter.sv
//   vvp -n tb.vvp +seed=1 +ops=20000
`timescale 1ns/1ps
`default_nettype none

module tb_sdram128_burstn_adapter;
    logic clk = 0, rst = 1;
    always #10 clk = ~clk;

    logic         write = 0, read = 0;
    logic [24:0]  adrs = 0;
    logic [127:0] din = 0, dout;
    logic [15:0]  enable = 0, dropped;
    logic [3:0]   burst = 0;
    logic         ack, ready, stray;
    logic         ctrl_ready = 0, req_valid, req_we, req_ready, rd_valid;
    logic [23:0]  req_addr;
    logic [31:0]  req_wdata, rd_data;
    logic [3:0]   req_be;
    logic [2:0]   req_tag, rd_tag;

    sdram128_burstn_wordside dut (.*);

    integer seed, seed0, ops, errors = 0, reads = 0, writes = 0, words_rd = 0, words_wr = 0;
    integer max_lat = 6, ready_pct = 70;

    // ---- memory: default contents are a hash of the word address
    // Icarus has no associative arrays with vector keys: the address windows used
    // below map one-to-one onto {a[23], a[22], a[19], a[11:0]}.
    logic [31:0] mem [0:32767];
    bit          mem_v [0:32767];
    function automatic int key(input logic [23:0] a);
        return {a[23], a[22], a[19], a[11:0]};
    endfunction
    function automatic logic [31:0] word_at(input logic [23:0] a);
        return mem_v[key(a)] ? mem[key(a)] : word_at_default(a);
    endfunction

    // ---- behavioural word controller: accept with random backpressure, return
    // reads in order after a random latency (>= 1 cycle)
    logic [31:0] q_data [$];
    logic [2:0]  q_tag  [$];
    integer      q_due  [$];
    integer      cyc = 0;
    always_ff @(posedge clk) cyc <= cyc + 1;

    always @(negedge clk) req_ready = ctrl_ready && req_valid && ($urandom(seed) % 100 < ready_pct);

    always @(posedge clk) begin
        rd_valid <= 1'b0;
        if (q_due.size() != 0 && q_due[0] <= cyc) begin
            rd_valid <= 1'b1; rd_data <= q_data[0]; rd_tag <= q_tag[0];
            void'(q_data.pop_front()); void'(q_tag.pop_front()); void'(q_due.pop_front());
        end
        if (req_valid && req_ready) begin
            if (req_we) begin
                logic [31:0] w;
                w = word_at(req_addr);
                for (int b = 0; b < 4; b++) if (req_be[b]) w[b * 8 +: 8] = req_wdata[b * 8 +: 8];
                mem[key(req_addr)] = w; mem_v[key(req_addr)] = 1;
                words_wr++;
            end else begin
                integer due;
                due = cyc + 1 + ($urandom(seed) % max_lat);
                if (q_due.size() != 0 && due < q_due[q_due.size() - 1]) due = q_due[q_due.size() - 1];
                q_data.push_back(word_at(req_addr)); q_tag.push_back(req_tag); q_due.push_back(due);
                words_rd++;
            end
        end
    end

    // ---- reference halfword model kept in step with the issued writes
    logic [15:0] ref_mem [0:65535];
    bit          ref_v [0:65535];
    function automatic int hkey(input logic [24:0] a);
        return {key(a[24:1]), a[0]};
    endfunction
    function automatic logic [15:0] ref_get(input logic [24:0] a);
        logic [31:0] w;
        w = word_at_default(a[24:1]);
        return ref_v[hkey(a)] ? ref_mem[hkey(a)] : (a[0] ? w[31:16] : w[15:0]);
    endfunction
    function automatic logic [31:0] word_at_default(input logic [23:0] a);
        return (a * 32'h9E3779B1) ^ 32'h5A5AC3C3;
    endfunction

    // ---- core-like driver
    logic ack_q = 0;
    always @(posedge clk) ack_q <= ack;

    task automatic one_cycle_strobe(input bit is_write, input logic [24:0] a, input logic [3:0] b,
                                    input logic [127:0] d, input logic [15:0] e);
        @(negedge clk);
        write = is_write; read = !is_write; adrs = a; burst = b; din = d; enable = e;
        #1;
        if (ack) begin $display("ERROR ack high during strobe"); errors++; end
        @(negedge clk);
        write = 0; read = 0;
        if (ack_q) begin $display("ERROR registered ack still high after strobe"); errors++; end
    endtask

    task automatic wait_ack_q();
        integer guard;
        guard = 0;
        while (!ack_q) begin
            @(negedge clk);
            guard++;
            if (guard > 2000) begin $display("ERROR timeout waiting for ack"); errors++; $finish; end
        end
    endtask

    function automatic logic [24:0] rand_addr();
        case ($urandom(seed) % 4)
        0: return 25'h0000000 + ($urandom(seed) % 64);
        1: return 25'h0100000 + ($urandom(seed) % 64);
        2: return 25'h1FFFFC0 + ($urandom(seed) % 64);   // includes the top-of-device wrap
        default: return 25'h0800000 + ($urandom(seed) % 4096);
        endcase
    endfunction

    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        seed0 = seed;
        if (!$value$plusargs("ops=%d", ops)) ops = 20000;
        repeat (3) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);
        if (ack) begin $display("ERROR ack before controller ready"); errors++; end
        ctrl_ready = 1;
        @(negedge clk);
        wait_ack_q();
        for (int n = 0; n < ops; n++) begin
            bit is_w;
            logic [24:0] a;
            logic [3:0]  b, len;
            logic [127:0] d;
            logic [15:0] e;
            if (n == ops / 2) begin max_lat = 1; ready_pct = 100; end   // back-to-back phase
            is_w = $urandom(seed) % 2;
            a = rand_addr();
            b = $urandom(seed) % 16;
            len = (b == 0 || b > 8) ? 8 : b;
            d = {$urandom(seed), $urandom(seed), $urandom(seed), $urandom(seed)};
            e = $urandom(seed);
            one_cycle_strobe(is_w, a, b, d, e);
            if (is_w) begin
                writes++;
                for (int h = 0; h < len; h++) begin
                    logic [24:0] ha;
                    logic [15:0] v;
                    ha = a + h;
                    v = ref_get(ha);
                    if (e[2 * h])     v[7:0]  = d[h * 16 +: 8];
                    if (e[2 * h + 1]) v[15:8] = d[h * 16 + 8 +: 8];
                    ref_mem[hkey(ha)] = v; ref_v[hkey(ha)] = 1;
                end
                wait_ack_q();
            end else begin
                reads++;
                wait_ack_q();
                for (int h = 0; h < len; h++) begin
                    logic [15:0] exp;
                    exp = ref_get(a + h);
                    if (dout[h * 16 +: 16] !== exp) begin
                        if (errors < 10)
                            $display("ERROR read a=%h burst=%0d half %0d got %h exp %h", a, b, h, dout[h * 16 +: 16], exp);
                        errors++;
                    end
                end
            end
            // sometimes keep issuing on the first ack cycle (wram_clear pattern), else idle a bit
            if ($urandom(seed) % 2) repeat ($urandom(seed) % 3) @(negedge clk);
        end
        // a strobe while busy must be counted, not silently merged
        @(negedge clk);
        read = 1; adrs = 0; burst = 8;
        @(negedge clk);
        read = 1;               // second strobe while busy
        @(negedge clk);
        read = 0;
        wait_ack_q();
        if (dropped != 1) begin $display("ERROR dropped=%0d, expected 1", dropped); errors++; end
        if (stray) begin $display("ERROR stray read data"); errors++; end
        if (q_due.size() != 0) begin $display("ERROR %0d unconsumed read words", q_due.size()); errors++; end
        if (errors == 0)
            $display("PASS tb_sdram128_burstn_adapter: %0d reads, %0d writes, %0d/%0d words rd/wr, seed %0d",
                     reads, writes, words_rd, words_wr, seed0);
        else
            $display("FAIL tb_sdram128_burstn_adapter: %0d errors", errors);
        $finish;
    end
endmodule

`default_nettype wire
