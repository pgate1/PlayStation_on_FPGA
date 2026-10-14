// SPDX-License-Identifier: MIT
// Full-chain BIOS boot simulation of the prepared Pocket top (Q-L1-16).
//
// Device under test: core_top.v as prepared by tools/pocket/prepare_ps1_project.py
// (loader FIFOs, synchronisers, SDRAM/SRAM glue, the sflc-translated `core` with
// its loader stages, SDRAM arbitration and view RAM, sdram128_burstn_adapter ->
// sdr_ctrl -> sdr_phy). Only the two Intel IP blocks are replaced
// (sim_ip_stubs.sv: main_pll_0002 -> clocks, mf_datatable -> RAM; sdr_phy uses
// its own VERILATOR branch instead of ALTDDIO).
//
// Around it: clk_74a, an APF host model on the bridge (status/reset commands,
// target data-slot reads answered with bridge writes at +wr_interval clk_74a
// cycles per word, slot 0x20 = +slot20, slot 0x40 = +slot40), a behavioural SDR
// SDRAM (CL 3, BL 2, read data +tout_ps after the SDRAM clock edge; the model of
// Pocket/tb/tb_sdram128_burstn_pins.sv with the full 32M x 16), an async SRAM,
// an SDRAM scoreboard (every command accepted by the adapter is replayed into a
// reference memory; every completed read is compared), a detector for the
// core-internal CPU/GPU-SPU strobe collision (T11), a runaway-PC detector and a
// capture of the VGA output as 320x240 PPM frames.
//
// Plusargs: +slot20=<file> +slot40=<file> +outdir=<dir> +cycles=<core cycles>
//   +frames_every=<n> +wr_interval=<clk_74a cycles per loader word> +tout_ps=<n>
//   +status_every=<core cycles> +sdram_init=<0|1: zero or pattern>
//   +stop_on_runaway=<cycles to run after the first runaway PC, 0 = keep going>
//   +fast_1sec=<1: skip most of the core's one-second start delay after the loader stages>
`timescale 1ns/1ps
module tb_pocket_boot;
    // ---------------- clocks ----------------
    reg clk_74a = 0;
    always #6.734 clk_74a = ~clk_74a;                    // 74.25 MHz

    // ---------------- bridge ----------------
    reg  [31:0] bridge_addr = 0, bridge_wr_data = 0;
    reg         bridge_rd = 0, bridge_wr = 0;
    wire [31:0] bridge_rd_data;
    wire        bridge_endian_little;

    // ---------------- pads ----------------
    wire [12:0] dram_a; wire [1:0] dram_ba; wire [15:0] dram_dq; wire [1:0] dram_dqm;
    wire dram_clk, dram_cke, dram_ras_n, dram_cas_n, dram_we_n;
    wire [16:0] sram_a; wire [15:0] sram_dq; wire sram_oe_n, sram_we_n, sram_ub_n, sram_lb_n;
    wire [23:0] video_rgb; wire video_rgb_clock, video_rgb_clock_90, video_de, video_skip, video_vs, video_hs;
    wire audio_mclk, audio_dac, audio_lrck;

    core_top dut (
        .clk_74a(clk_74a), .clk_74b(clk_74a),
        .cram0_wait(1'b0), .cram1_wait(1'b0), .vblank(1'b0), .dbg_rx(1'b1), .user2(1'b0),
        .port_ir_rx(1'b0), .audio_adc(1'b0),
        .dram_a(dram_a), .dram_ba(dram_ba), .dram_dq(dram_dq), .dram_dqm(dram_dqm), .dram_clk(dram_clk),
        .dram_cke(dram_cke), .dram_ras_n(dram_ras_n), .dram_cas_n(dram_cas_n), .dram_we_n(dram_we_n),
        .sram_a(sram_a), .sram_dq(sram_dq), .sram_oe_n(sram_oe_n), .sram_we_n(sram_we_n),
        .sram_ub_n(sram_ub_n), .sram_lb_n(sram_lb_n),
        .video_rgb(video_rgb), .video_rgb_clock(video_rgb_clock), .video_rgb_clock_90(video_rgb_clock_90),
        .video_de(video_de), .video_skip(video_skip), .video_vs(video_vs), .video_hs(video_hs),
        .audio_mclk(audio_mclk), .audio_dac(audio_dac), .audio_lrck(audio_lrck),
        .bridge_endian_little(bridge_endian_little), .bridge_addr(bridge_addr), .bridge_rd(bridge_rd),
        .bridge_rd_data(bridge_rd_data), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
        .cont1_key(32'd0), .cont2_key(32'd0), .cont3_key(32'd0), .cont4_key(32'd0),
        .cont1_joy(32'd0), .cont2_joy(32'd0), .cont3_joy(32'd0), .cont4_joy(32'd0),
        .cont1_trig(16'd0), .cont2_trig(16'd0), .cont3_trig(16'd0), .cont4_trig(16'd0));

    wire clk_core = video_rgb_clock;                     // = clk_50 (PLL outclk_3 = outclk_0 in the stub)

    // ---------------- plusargs ----------------
    string slot20_file, slot40_file, outdir;
    longint max_cycles = 200000000;
    integer frames_every = 30, wr_interval = 12, tout_ps = 7000, status_every = 4000000;
    integer sdram_init = 1, stop_on_runaway = 2000000, fast_1sec = 1;

    // ---------------- SDRAM model (32M x 16, CL 3, BL 2) ----------------
    // halfword index = {row[12:0], bank[1:0], col[9:0]}: what sdr_ctrl maps a 25-bit
    // halfword address to (word a[23:11] row, a[10:9] bank, a[8:0] column pair).
    logic [15:0] smem [0:33554431];
    function automatic logic [15:0] init_half(input int k);
        return sdram_init ? (16'(k * 16'h9E37) ^ 16'hA5C3) : 16'h0000;
    endfunction
    function automatic int key(input logic [1:0] ba, input logic [12:0] row, input logic [9:0] col);
        return {7'd0, row, ba, col};
    endfunction
    logic [3:0]  open_b = 0;
    logic [12:0] row_b [4];
    logic        mrs_ok = 0;
    integer      edge_n = 0, sdram_errors = 0, acts = 0, refs = 0, rd_beats = 0, wr_beats = 0;
    integer      rd_key [0:7];
    bit          rd_pend [0:7];
    bit          wr_pend = 0, drove = 0;
    integer      wr_key;
    logic [15:0] dq_out = 0;
    logic        dq_en = 0;
    assign dram_dq = dq_en ? dq_out : 16'bz;
    initial for (int i = 0; i < 8; i++) rd_pend[i] = 0;
    real t_out, t_rel;

    task automatic write_beat(input int k);
        logic [15:0] v;
        v = smem[k];
        if (!dram_dqm[0]) v[7:0]  = dram_dq[7:0];
        if (!dram_dqm[1]) v[15:8] = dram_dq[15:8];
        smem[k] = v; wr_beats++;
    endtask

    always @(posedge dram_clk) if (dram_cke) begin
        automatic int slot = edge_n % 8;
        if (wr_pend) begin write_beat(wr_key); wr_pend = 0; end
        if (rd_pend[slot]) begin
            automatic logic [15:0] v = smem[rd_key[slot]];
            rd_pend[slot] = 0; drove = 1; rd_beats++;
            fork begin #(t_out) dq_out = v; dq_en = 1; end join_none
        end else if (drove) begin
            drove = 0;
            fork begin #(t_rel) dq_en = 0; end join_none
        end
        case ({dram_ras_n, dram_cas_n, dram_we_n})
        3'b011: begin
            if (open_b[dram_ba]) begin $display("SDRAM ERROR t=%0t ACT to open bank %0d", $time, dram_ba); sdram_errors++; end
            open_b[dram_ba] = 1; row_b[dram_ba] = dram_a; acts++;
        end
        3'b010: if (dram_a[10]) open_b = 0; else open_b[dram_ba] = 0;
        3'b001: begin
            if (open_b != 0) begin $display("SDRAM ERROR t=%0t REFRESH with open banks", $time); sdram_errors++; end
            refs++;
        end
        3'b000: mrs_ok = (dram_a[6:4] == 3'd3) && (dram_a[2:0] == 3'd1) && !dram_a[3];
        3'b101, 3'b100: begin
            if (!mrs_ok) begin $display("SDRAM ERROR t=%0t access before MRS CL3 BL2", $time); sdram_errors++; end
            if (!open_b[dram_ba]) begin $display("SDRAM ERROR t=%0t access to closed bank %0d", $time, dram_ba); sdram_errors++; end
            if (dram_a[0]) begin $display("SDRAM ERROR t=%0t odd BL2 column", $time); sdram_errors++; end
            if (dram_we_n == 1'b1) begin   // READ: beats at edges n+CL-1 and n+CL (+tAC)
                rd_pend[(edge_n + 2) % 8] = 1; rd_key[(edge_n + 2) % 8] = key(dram_ba, row_b[dram_ba], dram_a[9:0]);
                rd_pend[(edge_n + 3) % 8] = 1; rd_key[(edge_n + 3) % 8] = key(dram_ba, row_b[dram_ba], dram_a[9:0] | 10'd1);
            end else begin                  // WRITE: beat 0 now, beat 1 next edge
                write_beat(key(dram_ba, row_b[dram_ba], dram_a[9:0]));
                wr_pend = 1; wr_key = key(dram_ba, row_b[dram_ba], dram_a[9:0] | 10'd1);
            end
        end
        default: ;
        endcase
        edge_n++;
    end

    // ---------------- async SRAM model (128K x 16) ----------------
    logic [15:0] sram_mem [0:131071];
    assign sram_dq = (!sram_oe_n && sram_we_n) ? sram_mem[sram_a] : 16'bz;
    always @(posedge sram_we_n) begin
        if (!sram_lb_n) sram_mem[sram_a][7:0]  <= sram_dq[7:0];
        if (!sram_ub_n) sram_mem[sram_a][15:8] <= sram_dq[15:8];
    end

    // ---------------- slot images ----------------
    logic [7:0] slot20 [0:524287];
    logic [7:0] slot40 [0:33554431];
    integer slot20_len = 0, slot40_len = 0;

    // ---------------- APF host model ----------------
    function automatic logic [31:0] bswap(input logic [31:0] v);
        return {v[7:0], v[15:8], v[23:16], v[31:24]};
    endfunction
    task automatic bridge_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk_74a); bridge_addr <= addr; bridge_wr_data <= data; bridge_wr <= 1;
        @(posedge clk_74a); bridge_wr <= 0;
    endtask
    task automatic bridge_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk_74a); bridge_addr <= addr; bridge_rd <= 1;
        @(posedge clk_74a); bridge_rd <= 0;
        @(posedge clk_74a); #1 data = bridge_rd_data;
    endtask
    // registers of core_bridge_cmd: the host byte-swaps (bridge_endian_little = 1)
    task automatic reg_write(input logic [31:0] addr, input logic [31:0] v); bridge_write(addr, bswap(v)); endtask
    task automatic reg_read(input logic [31:0] addr, output logic [31:0] v);
        logic [31:0] raw; bridge_read(addr, raw); v = bswap(raw);
    endtask
    task automatic host_cmd(input logic [15:0] cmd, output logic [15:0] result);
        logic [31:0] r; integer guard;
        reg_write(32'hF8000000, {16'h434D, cmd});
        guard = 0;
        do begin
            repeat (8) @(posedge clk_74a);
            reg_read(32'hF8000000, r);
            if (++guard > 100000) begin $display("FAIL host command %h never answered", cmd); $finish; end
        end while (r[31:16] != 16'h4F4B);
        result = r[15:0];
    endtask

    integer loads = 0, load_words = 0;
    longint load_start_cyc = 0, bios_start_cyc = 0;
    logic [15:0] last_slot_id = 0;
    logic        slot20_loaded = 0;
    task automatic dataslot_read_op();
        logic [31:0] id, off, baddr, len, word;
        integer nwords;
        reg_write(32'hF8001000, 32'h62750180);        // busy
        reg_read(32'hF8001020, id); reg_read(32'hF8001024, off);
        reg_read(32'hF8001028, baddr); reg_read(32'hF800102C, len);
        $display("HOST dataslot read id=%h offset=%h bridgeaddr=%h length=%0d (core cycle %0d, t=%0t)",
                 id[15:0], off, baddr, len, cyc, $time);
        loads++; last_slot_id = id[15:0]; load_start_cyc = cyc;
        if (id[15:0] == 16'h0020) bios_start_cyc = cyc;
        nwords = (len + 3) / 4;
        if ((id[15:0] == 16'h0020 && slot20_len == 0) || (id[15:0] == 16'h0040 && slot40_len == 0) ||
            (id[15:0] != 16'h0020 && id[15:0] != 16'h0040)) begin
            repeat (200) @(posedge clk_74a);
            $display("HOST slot %h not present: error 2", id[15:0]);
            reg_write(32'hF8001000, 32'h6F6B0002);
            return;
        end
        for (int w = 0; w < nwords; w++) begin
            automatic int b = off + 4 * w;
            if (id[15:0] == 16'h0020)
                word = {slot20[(b + 3) % 524288], slot20[(b + 2) % 524288], slot20[(b + 1) % 524288], slot20[b % 524288]};
            else
                word = {slot40[(b + 3) % 33554432], slot40[(b + 2) % 33554432], slot40[(b + 1) % 33554432], slot40[b % 33554432]};
            repeat (wr_interval - 2) @(posedge clk_74a);
            bridge_write(baddr + 4 * w, word);
            load_words++;
        end
        repeat (64) @(posedge clk_74a);
        reg_write(32'hF8001000, 32'h6F6B0000);
        $display("HOST dataslot read id=%h done: %0d words (core cycle %0d)", id[15:0], nwords, cyc);
    endtask

    logic host_started = 0;
    initial begin : host
        logic [15:0] res; logic [31:0] t0; integer idle;
        repeat (400) @(posedge clk_74a);
        do host_cmd(16'h0000, res); while (res < 2);     // boot done
        $display("HOST status %0d at t=%0t", res, $time);
        host_cmd(16'h0011, res);                           // reset exit
        $display("HOST reset exit (core cycle %0d, t=%0t)", cyc, $time);
        host_started = 1;
        forever begin
            repeat (16) @(posedge clk_74a);
            reg_read(32'hF8001000, t0);
            if (t0[31:16] == 16'h636D) begin
                case (t0[15:0])
                16'h0140: begin reg_write(32'hF8001000, 32'h6F6B0000); $display("HOST ready-to-run acked"); end
                16'h0180: dataslot_read_op();
                default: begin $display("HOST unknown target command %h", t0); reg_write(32'hF8001000, 32'h6F6BFFFF); end
                endcase
            end
        end
    end

    // ---------------- SDRAM scoreboard (adapter command side, core clock) ----------------
    logic [15:0] ref_mem [0:33554431];
    longint sb_reads = 0, sb_writes = 0, sb_mismatch = 0, sb_ops_loader = 0, sb_ops_cpu = 0, sb_ops_alt = 0;
    logic        sb_pending = 0;
    logic [24:0] sb_adrs; integer sb_len; string sb_master; logic sb_write = 0;
    logic drop_watch = 0; logic [24:0] drop_adrs; integer drop_len; longint drop_cyc;
    longint      sb_cycle;
    wire cpu_strobe = dut.CU.__sfl_port_2_WRAM_READ | dut.CU.__sfl_port_2_WRAM_WRITE | dut.CU.__sfl_port_2_BIOS_READ;
    wire alt_req = dut.CU.__sfl_port_2_vram_read_req | dut.CU.__sfl_port_2_vram_write_req |
                   dut.CU.__sfl_port_2_spu_mem_read_req | dut.CU.__sfl_port_2_spu_mem_write_req;
    wire alt_open = ~(dut.CU.gpu_read_wait_ack | dut.CU.gpu_write_wait_ack | dut.CU.spu_wait_ack | ~dut.CU.sdram_ack);
    wire collision_cond = cpu_strobe & alt_open & alt_req;    // T11-less: both strobe, arguments ORed
    wire rw_both = dut.core_sdram_write & dut.core_sdram_read;
    longint collisions = 0, rw_boths = 0, dropped_seen = 0;
    longint cyc = 0;
    function automatic string master_name();
        if (dut.ldf_go) return "loader";
        if (cpu_strobe) return dut.CU.__sfl_port_2_WRAM_WRITE ? "cpu-write" : (dut.CU.__sfl_port_2_BIOS_READ ? "cpu-bios" : "cpu-read");
        if (alt_open & (dut.CU.__sfl_port_2_vram_read_req | dut.CU.__sfl_port_2_vram_write_req)) return "gpu";
        if (alt_open & alt_req) return "spu";
        return "core-stage";    // wram_clear
    endfunction

    always @(posedge clk_core) if (dut.reset_n) begin
        automatic int len = (dut.sdram_burst == 0 || dut.sdram_burst > 8) ? 8 : dut.sdram_burst;
        if (collision_cond) begin
            collisions++;
            if (collisions <= 5)
                $display("COLLISION #%0d cycle=%0d pc=%h: CPU strobe (rd=%b wr=%b bios=%b A=%h Word=%0d) and GPU/SPU request (vr=%b vw=%b sr=%b sw=%b) in one cycle; core_sdram_read=%b write=%b adrs=%h burst=%0d",
                         collisions, cyc, dut.CU.psx.pc_out, dut.CU.__sfl_port_2_WRAM_READ, dut.CU.__sfl_port_2_WRAM_WRITE,
                         dut.CU.__sfl_port_2_BIOS_READ, dut.CU.__sfl_port_2_A, dut.CU.__sfl_port_2_Word,
                         dut.CU.__sfl_port_2_vram_read_req, dut.CU.__sfl_port_2_vram_write_req,
                         dut.CU.__sfl_port_2_spu_mem_read_req, dut.CU.__sfl_port_2_spu_mem_write_req,
                         dut.core_sdram_read, dut.core_sdram_write, dut.core_sdram_adrs, dut.core_sdram_burst);
        end
        if (rw_both) rw_boths++;
        if ((dut.sdram_read | dut.sdram_write) && !dut.sdram_mem_ready) begin
            dropped_seen++;
            if (dropped_seen <= 8) begin
                $display("DROPPED #%0d cycle=%0d pc=%h master=%s rd=%b wr=%b adrs=%h burst=%0d: adapter busy with %s %s adrs=%h burst=%0d issued cycle=%0d (gpu_wait=%b%b spu_wait=%b sdram_ack=%b)",
                         dropped_seen, cyc, dut.CU.psx.pc_out, master_name(), dut.sdram_read, dut.sdram_write, dut.sdram_adrs, dut.sdram_burst,
                         sb_master, sb_write ? "write" : "read", sb_adrs, sb_len, sb_cycle,
                         dut.CU.gpu_read_wait_ack, dut.CU.gpu_write_wait_ack, dut.CU.spu_wait_ack, dut.CU.sdram_ack);
                if (dut.sdram_read && cpu_strobe) begin
                    drop_watch = 1; drop_adrs = dut.sdram_adrs; drop_len = len; drop_cyc = cyc;
                end
            end
        end
        // the CPU takes the next ack as its own: show what it receives against what it asked for
        if (drop_watch && dut.CU.sdram_ack && dut.CU.__sfl_port_2_wram_ack) begin
            drop_watch = 0;
            $display("CPU READ GOT OTHER DATA: dropped read adrs=%h (cycle %0d) acked at cycle=%0d with sdram_dout[31:0]=%h (of the %s op), correct data would be %h%h",
                     drop_adrs, drop_cyc, cyc, dut.sdram_dout[31:0], sb_master,
                     ref_mem[(drop_adrs + 1) & 25'h1FFFFFF], ref_mem[drop_adrs & 25'h1FFFFFF]);
        end
        // completion of a pending read: ready is back and dout holds the burst
        if (sb_pending && dut.sdram_mem_ready) begin
            sb_pending = 0;
            for (int h = 0; h < sb_len; h++) begin
                automatic logic [15:0] exp = ref_mem[(sb_adrs + h) & 25'h1FFFFFF];
                automatic logic [15:0] got = dut.sdram_dout[h * 16 +: 16];
                if (got !== exp) begin
                    sb_mismatch++;
                    if (sb_mismatch <= 10)
                        $display("SDRAM MISMATCH #%0d: read issued cycle=%0d by %s adrs=%h burst=%0d half %0d: got %h expected %h (completed cycle=%0d pc=%h)",
                                 sb_mismatch, sb_cycle, sb_master, sb_adrs, sb_len, h, got, exp, cyc, dut.CU.psx.pc_out);
                end
            end
        end
        if ((dut.sdram_read | dut.sdram_write) && dut.sdram_mem_ready) begin
            if (dut.ldf_go) sb_ops_loader++; else if (cpu_strobe) sb_ops_cpu++; else sb_ops_alt++;
            sb_master = master_name(); sb_cycle = cyc; sb_adrs = dut.sdram_adrs; sb_len = len; sb_write = dut.sdram_write;
            if (dut.sdram_write) begin
                sb_writes++;
                for (int h = 0; h < len; h++) begin
                    automatic int a = (dut.sdram_adrs + h) & 25'h1FFFFFF;
                    if (dut.sdram_enable[2 * h])     ref_mem[a][7:0]  = dut.sdram_din[h * 16 +: 8];
                    if (dut.sdram_enable[2 * h + 1]) ref_mem[a][15:8] = dut.sdram_din[h * 16 + 8 +: 8];
                end
            end else begin
                sb_reads++; sb_pending = 1;
            end
        end
    end

    // ---------------- BIOS image check after the slot 0x20 load ----------------
    always @(negedge dut.ram_reloading) if (last_slot_id == 16'h0020 && slot20_len == 524288) begin
        automatic int bad = 0;
        automatic longint t0 = bios_start_cyc;
        wait (dut.ldf_level == 0);
        repeat (64) @(posedge clk_core);
        for (int i = 0; i < 262144; i++) begin
            automatic logic [15:0] exp = {slot20[2 * i + 1], slot20[2 * i]};
            if (smem[25'h800000 + i] !== exp) begin
                if (bad < 5) $display("BIOS WORD WRONG halfword %h: sdram %h file %h", i, smem[25'h800000 + i], exp);
                bad++;
            end
        end
        $display("BIOS CHECK: %0d of 262144 halfwords wrong in SDRAM after load (%0d words bridged in %0d core cycles, ldf_ovf=%b dropped=%0d)",
                 bad, load_words, cyc - t0, dut.ldf_ovf_74, dut.sdram_dropped);
        slot20_loaded = 1;
    end

    // ---------------- VGA capture (640x480 scan -> 320x240) ----------------
    reg [23:0] fb [0:239][0:319];
    integer vx = 0, vy = 0, frames = 0;
    longint pixels = 0;
    reg hs_d = 1, vs_d = 1;
    always @(posedge clk_core) begin
        hs_d <= video_hs; vs_d <= video_vs;
        if (video_de) begin
            if (!vx[0] && !vy[0] && vx / 2 < 320 && vy / 2 < 240) fb[vy / 2][vx / 2] <= video_rgb;
            vx <= vx + 1; pixels++;
        end
        if (hs_d && !video_hs) begin vx <= 0; vy <= vy + 1; end
        if (vs_d && !video_vs) begin vy <= 0; frames <= frames + 1; end
    end

    task automatic dump_frame(input integer n);
        integer fd, x, y; string fn;
        begin
            fn = $sformatf("%s/frame_%05d.ppm", outdir, n);
            fd = $fopen(fn, "wb");
            $fwrite(fd, "P6\n320 240\n255\n");
            for (y = 0; y < 240; y++) for (x = 0; x < 320; x++)
                $fwrite(fd, "%c%c%c", fb[y][x][23:16], fb[y][x][15:8], fb[y][x][7:0]);
            $fclose(fd);
        end
    endtask

    // +fast_1sec=1: the core waits one second (count_1sec, core.sflp) before psx_run_ok;
    // skip most of it once the loader stages are done (exe_read_ok)
    initial begin
        wait (fast_1sec && dut.CU.exe_read_ok);
        repeat (1000) @(posedge clk_core);
        if (dut.CU.count_1sec < 26'd39000000) begin
            force dut.CU.count_1sec = 26'd39000000;
            @(posedge clk_core);
            release dut.CU.count_1sec;
            $display("FAST_1SEC: count_1sec advanced at cycle=%0d", cyc);
        end
    end

    // ---------------- run control / monitors ----------------
    function automatic bit pc_ok(input logic [31:0] pc);
        automatic logic [28:0] p = pc[28:0];
        return (p < 29'h200000) || (p >= 29'h1FC00000 && p < 29'h1FC80000) || (p >= 29'h1F800000 && p < 29'h1F800400);
    endfunction
    logic [31:0] pc_hist [0:31]; longint pc_hist_cyc [0:31]; integer pc_hist_n = 0;
    logic [31:0] pc_last = 0;
    longint runaway_cycle = -1, first_bad_cycle = -1;
    integer last_dumped = -1, kernel_seen = 0, bios_seen = 0, run_seen = 0, exe_seen = 0, reset_seen = 0;

    always @(posedge clk_core) begin
        if (dut.reset_n) cyc++;
        if (dut.reset_n && !reset_seen) begin reset_seen = 1; $display("CORE reset released at t=%0t", $time); end
        if (dut.CU.psx.pc_out != pc_last) begin
            pc_last = dut.CU.psx.pc_out;
            pc_hist[pc_hist_n % 32] = pc_last; pc_hist_cyc[pc_hist_n % 32] = cyc; pc_hist_n++;
        end
        if (dut.CU.f_bios && !bios_seen) begin bios_seen = 1; $display("CORE f_bios set (BIOS mode) cycle=%0d", cyc); end
        if (dut.CU.exe_read_ok && !exe_seen) begin exe_seen = 1; $display("CORE exe_read_ok cycle=%0d", cyc); end
        if (dut.CU.psx_run_ok && !run_seen) begin run_seen = 1; $display("CORE psx_run_ok (CPU starts) cycle=%0d t=%0t", cyc, $time); end
        if (dut.CU.psx.kernel_ok && !kernel_seen) begin kernel_seen = 1; $display("KERNEL_OK cycle=%0d pc=%h", cyc, dut.CU.psx.pc_out); end
        if (run_seen && !pc_ok(dut.CU.psx.pc_out) && runaway_cycle < 0) begin
            runaway_cycle = cyc;
            $display("RUNAWAY PC %h at cycle=%0d t=%0t opcode=%h (collisions so far %0d, mismatches %0d, dropped %0d)",
                     dut.CU.psx.pc_out, cyc, $time, dut.CU.psx.opcode_out, collisions, sb_mismatch, dut.sdram_dropped);
            for (int i = (pc_hist_n > 32 ? pc_hist_n - 32 : 0); i < pc_hist_n; i++)
                $display("  pc history: cycle=%0d pc=%h", pc_hist_cyc[i % 32], pc_hist[i % 32]);
        end
        if (frames != last_dumped && frames % frames_every == 0 && run_seen) begin
            last_dumped = frames;
            dump_frame(frames);
            $display("FRAME %0d cycle=%0d pc=%h pixels=%0d", frames, cyc, dut.CU.psx.pc_out, pixels);
        end
        if (cyc % status_every == 0 && cyc != 0)
            $display("STATUS cycle=%0d t=%0t pc=%h halt=%h/%h core_halt=%h frames=%0d sdram ops loader/cpu/other=%0d/%0d/%0d reads=%0d mism=%0d collisions=%0d rw_both=%0d dropped=%0d stray=%b ldf_ovf=%b sdram_errs=%0d sram_lvl=%0d ldf_lvl=%0d reloading=%b",
                     cyc, $time, dut.CU.psx.pc_out, dut.CU.psx.halt_code, dut.CU.psx.halt_part, dut.CU.halt_code, frames,
                     sb_ops_loader, sb_ops_cpu, sb_ops_alt, sb_reads, sb_mismatch, collisions, rw_boths,
                     dut.sdram_dropped, dut.sdram_stray, dut.ldf_ovf_74, sdram_errors, dut.sfifo_lvl, dut.ldf_level, dut.ram_reloading);
        if (dut.CU.psx.halt_code != 0 || dut.CU.halt_code != 0) begin
            $display("HALT psx=%h part=%h core=%h pc=%h opcode=%h cycle=%0d t=%0t", dut.CU.psx.halt_code, dut.CU.psx.halt_part,
                     dut.CU.halt_code, dut.CU.psx.pc_out, dut.CU.psx.opcode_out, cyc, $time);
            dump_frame(99999); finish_report(); $finish;
        end
        if (runaway_cycle >= 0 && stop_on_runaway > 0 && cyc >= runaway_cycle + stop_on_runaway) begin
            dump_frame(99998); finish_report(); $finish;
        end
        if (cyc >= max_cycles) begin
            dump_frame(frames); finish_report(); $finish;
        end
    end

    task automatic finish_report();
        $display("END cycles=%0d t=%0t frames=%0d pc=%h runaway_cycle=%0d collisions=%0d rw_both=%0d sdram_mismatch=%0d dropped=%0d stray=%b ldf_ovf=%b sdram_model_errors=%0d acts=%0d refs=%0d loads=%0d kernel_ok=%0d bios_mode=%0d",
                 cyc, $time, frames, dut.CU.psx.pc_out, runaway_cycle, collisions, rw_boths, sb_mismatch,
                 dut.sdram_dropped, dut.sdram_stray, dut.ldf_ovf_74, sdram_errors, acts, refs, loads, kernel_seen, bios_seen);
    endtask

    initial begin
        integer fd;
        if (!$value$plusargs("slot20=%s", slot20_file)) begin $display("FAIL: +slot20=<BIOS.bin> required"); $finish; end
        if (!$value$plusargs("slot40=%s", slot40_file)) slot40_file = slot20_file;
        if (!$value$plusargs("outdir=%s", outdir)) outdir = ".";
        void'($value$plusargs("cycles=%d", max_cycles));
        void'($value$plusargs("frames_every=%d", frames_every));
        void'($value$plusargs("wr_interval=%d", wr_interval));
        void'($value$plusargs("tout_ps=%d", tout_ps));
        void'($value$plusargs("status_every=%d", status_every));
        void'($value$plusargs("sdram_init=%d", sdram_init));
        void'($value$plusargs("stop_on_runaway=%d", stop_on_runaway));
        void'($value$plusargs("fast_1sec=%d", fast_1sec));
        if (wr_interval < 3) wr_interval = 3;
        t_out = tout_ps / 1000.0; t_rel = 2.5 + (tout_ps - 5000) / 1000.0;
        fd = $fopen(slot20_file, "rb");
        if (fd == 0) begin $display("FAIL: cannot open %s", slot20_file); $finish; end
        slot20_len = $fread(slot20, fd); $fclose(fd);
        fd = $fopen(slot40_file, "rb");
        if (fd == 0) begin $display("FAIL: cannot open %s", slot40_file); $finish; end
        slot40_len = $fread(slot40, fd); $fclose(fd);
        $display("SLOT 0x20 %s (%0d bytes, first word %02x%02x%02x%02x); slot 0x40 %s (%0d bytes); wr_interval=%0d tout_ps=%0d",
                 slot20_file, slot20_len, slot20[3], slot20[2], slot20[1], slot20[0], slot40_file, slot40_len, wr_interval, tout_ps);
        for (int i = 0; i < 33554432; i++) begin smem[i] = init_half(i); ref_mem[i] = init_half(i); end
        for (int i = 0; i < 131072; i++) sram_mem[i] = 16'hFFFF;
        for (int y = 0; y < 240; y++) for (int x = 0; x < 320; x++) fb[y][x] = 0;
        $display("memories initialised, t=%0t", $time);
    end
endmodule
