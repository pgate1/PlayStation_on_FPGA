// SPDX-License-Identifier: MIT
// Pin-level smoke bench for sdram128_burstn_adapter: the full chain (wordside ->
// MIRLO64 sdr_ctrl -> sdr_phy) against a behavioural SDR SDRAM model (CL 3, BL 2)
// at clk 50 MHz / clk2x 100 MHz / SDRAM clock = clk2x + 90 degrees. Read data
// appears +tout_ps after the SDRAM clock edge CL-1 cycles after READ (tAC plus the
// board/IO round trip) and is released 2.5 ns (+ the same extra delay) after the
// next edge. sdr_phy's fixed read latency (RL 5) was tuned on MIRLO's board at
// 125.664 MHz. Here it captures correctly only for tout_ps in 10000..14000 (sweep,
// seed 1); 5000..9000 fail. Real tAC is ~5.4 ns, so at 100 MHz the SDRAM clock
// phase / IO delay must be chosen on hardware (later milestone). Default 12000.
// The model checks ACT/READ/WRITE/PRE/REF legality (open rows, refresh with all
// banks closed, MRS = CL 3 BL 2) but no AC timing.
// This is simulation evidence only, not a board timing statement.
// Run:
//   iverilog -g2012 -DVERILATOR -s tb_sdram128_burstn_pins -o tbp.vvp \
//     Pocket/rtl/sdram128_burstn_adapter.sv hdl/SDRAM/MIRLO64/sdr_ctrl.sv \
//     hdl/SDRAM/MIRLO64/sdr_phy.sv Pocket/tb/tb_sdram128_burstn_pins.sv
//   vvp -n tbp.vvp +seed=1 +ops=3000
`timescale 1ns/1ps
`default_nettype none

module tb_sdram128_burstn_pins;
    logic clk = 0, clk2x = 0, clk2x_90 = 0, p_reset = 1;
    // clk and clk2x change in the same active region (blocking), so no delta race
    // between the sys and sys2x flops of sdr_phy; clk rises with every other clk2x edge.
    initial forever begin #5 clk2x = 1; clk = ~clk; #5 clk2x = 0; end
    always @(clk2x) clk2x_90 <= #2.5 clk2x;

    logic         write = 0, read = 0;
    logic [24:0]  adrs = 0;
    logic [127:0] din = 0, dout;
    logic [15:0]  enable = 0, dropped;
    logic [3:0]   burst = 0;
    logic         ack, stray;
    wire  [12:0]  sdram_a;
    wire  [1:0]   sdram_ba, sdram_dm;
    wire          sdram_ras_n, sdram_cas_n, sdram_we_n, sdram_cke, sdram_clock;
    wire  [15:0]  sdram_dq;

    sdram128_burstn_adapter #(.T_INIT(40), .T_REFI(380)) dut (
        .clk, .clk2x, .clk2x_90, .p_reset, .write, .adrs, .din, .enable, .burst, .read, .dout,
        .manual_refresh(1'b0), .refresh_go(1'b0), .ack, .dropped, .stray,
        .sdram_a, .sdram_ba, .sdram_ras_n, .sdram_cas_n, .sdram_we_n, .sdram_cke, .sdram_dm,
        .sdram_dq, .sdram_clock);

    integer tout_ps = 12000;
    integer errors = 0, seed, seed0, ops, reads = 0, writes = 0, acts = 0, refs = 0;

    // ---- behavioural SDRAM. Address windows below map one-to-one onto the key.
    function automatic int key(input logic [1:0] ba, input logic [12:0] row, input logic [9:0] col);
        return {ba, row[12], row[11], row[8], col};
    endfunction
    function automatic logic [15:0] init_half(input int k);
        return 16'(k * 16'h9E37) ^ 16'hA5C3;
    endfunction
    logic [15:0] mem [0:32767];
    bit          mem_v [0:32767];
    function automatic logic [15:0] mem_get(input int k);
        return mem_v[k] ? mem[k] : init_half(k);
    endfunction
    logic [3:0]  open_b = 0;
    logic [12:0] row_b [4];
    logic        mrs_ok = 0;
    integer      edge_n = 0;
    integer      rd_key [0:7];
    bit          rd_pend [0:7];
    bit          wr_pend = 0;
    integer      wr_key;
    logic [15:0] dq_out = 0;
    logic        dq_en = 0;
    assign sdram_dq = dq_en ? dq_out : 16'bz;
    initial for (int i = 0; i < 8; i++) rd_pend[i] = 0;

    task automatic write_beat(input int k);
        logic [15:0] v;
        v = mem_get(k);
        if (!sdram_dm[0]) v[7:0]  = sdram_dq[7:0];
        if (!sdram_dm[1]) v[15:8] = sdram_dq[15:8];
        mem[k] = v; mem_v[k] = 1;
    endtask

    always @(posedge sdram_clock) if (sdram_cke) begin
        integer slot;
        slot = edge_n % 8;
        if (wr_pend) begin write_beat(wr_key); wr_pend = 0; end
        // read beat scheduled for this edge: data valid tAC after it
        dq_en <= #(2.5 + (tout_ps - 5000) / 1000.0) 1'b0;
        if (rd_pend[slot]) begin
            dq_out <= #(tout_ps / 1000.0) mem_get(rd_key[slot]);
            dq_en  <= #(tout_ps / 1000.0) 1'b1;
            rd_pend[slot] = 0;
        end
        case ({sdram_ras_n, sdram_cas_n, sdram_we_n})
        3'b011: begin
            if (open_b[sdram_ba]) begin $display("ERROR ACT to open bank %0d", sdram_ba); errors++; end
            open_b[sdram_ba] = 1; row_b[sdram_ba] = sdram_a; acts++;
        end
        3'b010: if (sdram_a[10]) open_b = 0; else open_b[sdram_ba] = 0;
        3'b001: begin
            if (open_b != 0) begin $display("ERROR REFRESH with open banks"); errors++; end
            refs++;
        end
        3'b000: mrs_ok = (sdram_a[6:4] == 3'd3) && (sdram_a[2:0] == 3'd1) && !sdram_a[3];
        3'b101, 3'b100: begin
            if (!mrs_ok) begin $display("ERROR access before MRS CL3 BL2"); errors++; end
            if (!open_b[sdram_ba]) begin $display("ERROR access to closed bank"); errors++; end
            if (sdram_a[0]) begin $display("ERROR odd BL2 column"); errors++; end
            if (sdram_we_n == 1'b1) begin   // READ: beats at edges n+CL-1 and n+CL (+tAC)
                rd_pend[(edge_n + 2) % 8] = 1; rd_key[(edge_n + 2) % 8] = key(sdram_ba, row_b[sdram_ba], sdram_a[9:0]);
                rd_pend[(edge_n + 3) % 8] = 1; rd_key[(edge_n + 3) % 8] = key(sdram_ba, row_b[sdram_ba], sdram_a[9:0] | 10'd1);
            end else begin                  // WRITE: beat 0 now, beat 1 next edge
                write_beat(key(sdram_ba, row_b[sdram_ba], sdram_a[9:0]));
                wr_pend = 1; wr_key = key(sdram_ba, row_b[sdram_ba], sdram_a[9:0] | 10'd1);
            end
        end
        default: ;
        endcase
        edge_n++;
    end

    // ---- reference: halfword address -> SDRAM key (row a[24:12], bank a[11:10], col a[9:0])
    function automatic int hkey(input logic [24:0] a);
        return key(a[11:10], a[24:12], a[9:0]);
    endfunction

    // what the bench intended to write (independent of the model's memory)
    logic [15:0] ref_mem [0:32767];
    bit          ref_v [0:32767];
    function automatic logic [15:0] ref_get(input int k);
        return ref_v[k] ? ref_mem[k] : init_half(k);
    endfunction

    logic ack_q = 0;
    always @(posedge clk) ack_q <= ack;

    task automatic wait_ack_q();
        integer guard;
        guard = 0;
        while (!ack_q) begin
            @(negedge clk);
            if (++guard > 20000) begin $display("ERROR timeout waiting for ack"); errors++; $finish; end
        end
    endtask

    function automatic logic [24:0] rand_addr();
        case ($urandom(seed) % 4)
        0: return 25'h0000000 + ($urandom(seed) % 3000);     // crosses banks within row 0
        1: return 25'h0100000 + ($urandom(seed) % 64);
        2: return 25'h1FFFFC0 + ($urandom(seed) % 64);
        default: return 25'h0800000 + ($urandom(seed) % 64);
        endcase
    endfunction

    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        if (!$value$plusargs("ops=%d", ops)) ops = 3000;
        void'($value$plusargs("tout_ps=%d", tout_ps));
        seed0 = seed;
        #100 p_reset = 0;
        @(negedge clk);
        wait_ack_q();
        for (int n = 0; n < ops; n++) begin
            bit is_w;
            logic [24:0] a;
            logic [3:0]  b, len;
            logic [127:0] d;
            logic [15:0] e;
            is_w = $urandom(seed) % 2;
            a = rand_addr();
            b = 1 + ($urandom(seed) % 8);
            len = b;
            d = {$urandom(seed), $urandom(seed), $urandom(seed), $urandom(seed)};
            e = $urandom(seed);
            @(negedge clk);
            write = is_w; read = !is_w; adrs = a; burst = b; din = d; enable = e;
            @(negedge clk);
            write = 0; read = 0;
            wait_ack_q();
            if (is_w) begin
                writes++;
                for (int h = 0; h < len; h++) begin
                    logic [15:0] v;
                    v = ref_get(hkey(a + h));
                    if (e[2 * h])     v[7:0]  = d[h * 16 +: 8];
                    if (e[2 * h + 1]) v[15:8] = d[h * 16 + 8 +: 8];
                    ref_mem[hkey(a + h)] = v; ref_v[hkey(a + h)] = 1;
                end
            end else begin
                reads++;
                for (int h = 0; h < len; h++) begin
                    logic [15:0] exp;
                    exp = ref_get(hkey(a + h));
                    if (dout[h * 16 +: 16] !== exp) begin
                        if (errors < 10)
                            $display("ERROR read a=%h burst=%0d half %0d got %h exp %h", a, b, h, dout[h * 16 +: 16], exp);
                        errors++;
                    end
                end
            end
        end
        if (dropped != 0 || stray) begin $display("ERROR dropped=%0d stray=%0d", dropped, stray); errors++; end
        if (refs < 2) begin $display("ERROR only %0d refreshes", refs); errors++; end
        if (errors == 0)
            $display("PASS tb_sdram128_burstn_pins: %0d reads, %0d writes, %0d ACT, %0d REF, tout %0d ps, seed %0d",
                     reads, writes, acts, refs, tout_ps, seed0);
        else
            $display("FAIL tb_sdram128_burstn_pins: %0d errors", errors);
        $finish;
    end
endmodule

`default_nettype wire
