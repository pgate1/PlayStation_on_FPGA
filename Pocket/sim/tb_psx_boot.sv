// SPDX-License-Identifier: MIT
// BIOS boot simulation of the sflc-translated PlayStation_core (Q-L1-15).
//
// Memory behaviour follows the upstream Pocket top (git show HEAD:Pocket/core.sflp,
// lines 240-353) with one 16-bit SDRAM:
//   main RAM: halfword address A<20:1>; reads of 1 halfword (Word 1/2, returned
//             <<16 when A<1>) or Word/2 halfwords from {A<20:2>,0}; byte/half/word
//             writes with lane masks.
//   BIOS:     same, at A<18:1>; word reads are 2 halfwords.
//   VRAM:     halfword address vram_adrs, burst 0b0||vram_burst halfwords, 64-bit
//             read data, 16-bit writes.
// ASSUMPTION (unresolved upstream): sdram_ack is the controller's registered
// "ready" level. It drops in the cycle a request is accepted and rises when the
// operation is complete; wram_ack/bios_ack follow it every cycle, VRAM acks only
// for a pending GPU access (core.sflp:260, 297, 302-341).
// SPU RAM (disabled upstream) is a separate 256K x 16 array here.
// The GPU's display writes (view_*) are captured into a 320x240 image and dumped
// as PPM files. Plusargs: +bios=<hex of 16-bit words> +cycles=N +outdir=<dir>
// +frames_every=K +lat=L
`timescale 1ns/1ps
module tb_psx_boot;
    reg clk = 0, reset = 1;
    always #10 clk = ~clk;            // 50 MHz

    // ---------------- DUT ----------------
    wire [20:0] A; wire [127:0] Din; wire WRAM_READ, BIOS_READ, WRAM_WRITE;
    wire [31:0] Dout; wire [4:0] Word;
    wire spu_wreq, spu_rreq; wire [17:0] spu_A; wire [15:0] spu_Din;
    reg  spu_ack = 0; reg [15:0] spu_Dout = 0;
    wire [20:0] voice_L, voice_R; wire [23:0] disp_env;
    wire view_on; wire [9:0] view_x; wire [8:0] view_y; wire [7:0] view_R, view_G, view_B;
    wire fill_view_on, dispW, dispH, display_flip, draw_notdisp_side;
    wire [18:0] vram_adrs; wire [15:0] vram_write_data; wire [2:0] vram_burst;
    wire vram_write_req, vram_read_req, vram_flush;
    reg  vram_read_ack = 0, vram_write_ack = 0;
    wire [31:0] file_adrs; wire file_read_req, file_preload;
    wire kernel_ok; wire [7:0] halt_code; wire [8:0] halt_part; wire [31:0] pc_out, opcode_out;
    wire [31:0] dbg, dbg2, dbg_cdr, dbg_gpu, dbg32; wire [7:0] dbg_cpu, dbg_pad; wire [15:0] dbg16;
    wire gpu_drawing, sio_waiting, mdec_waiting, vraming, dma_running;
    reg  run33 = 0, cpu_run = 0, vblank_begin = 0, vblank_end = 0;
    reg  sdram_ack = 0;               // registered ready, as core.sflp:112
    reg  [127:0] sdram_dout = 0;

    reg  [4:0]  last_Word; reg [20:0] last_A;
    // core.sflp:262-269
    assign Din = ((last_Word == 5'd1 || last_Word == 5'd2) && last_A[1]) ? (sdram_dout << 16) : sdram_dout;

    PlayStation_core psx (
        .p_reset(reset), .m_clock(clk), .cpu_run(cpu_run),
        .A(A), .Din(Din), .WRAM_READ(WRAM_READ), .wram_ack(sdram_ack), .BIOS_READ(BIOS_READ), .bios_ack(sdram_ack),
        .WRAM_WRITE(WRAM_WRITE), .Dout(Dout), .Word(Word),
        .exe_set(1'b0), .header_adrs(12'd0), .header_data(8'd0), .key_in(16'd0), .run33(run33),
        .spu_mem_write_req(spu_wreq), .spu_mem_read_req(spu_rreq), .spu_mem_A(spu_A), .spu_mem_Din(spu_Din),
        .spu_mem_ack(spu_ack), .spu_mem_Dout(spu_Dout), .sw_intpl_off(1'b0), .sw_reverb_off(1'b0),
        .voice_L(voice_L), .voice_R(voice_R), .disp_env(disp_env), .sw_outview_on(1'b0),
        .view_on(view_on), .view_x(view_x), .view_y(view_y), .view_R(view_R), .view_G(view_G), .view_B(view_B),
        .fill_view_on(fill_view_on), .dispW(dispW), .dispH(dispH), .display_flip(display_flip),
        .draw_notdisp_side(draw_notdisp_side), .vram_adrs(vram_adrs), .vram_write_data(vram_write_data),
        .vram_burst(vram_burst), .vram_write_req(vram_write_req), .vram_read_req(vram_read_req),
        .vram_read_ack(vram_read_ack), .vram_write_ack(vram_write_ack), .vram_read_data(sdram_dout[63:0]),
        .vram_flush(vram_flush), .sw_texcache_off(1'b0), .sw_kernel_run(1'b1),
        .vblank_begin(vblank_begin), .vblank_end(vblank_end), .sw_cache_off(1'b0),
        .sw_spu_off(1'b0), .sw_spuenv_off(1'b0), .stop(1'b0), .sw_view_half(1'b0), .sw_texture_off(1'b0),
        .file_adrs(file_adrs), .file_read_req(file_read_req), .file_preload(file_preload),
        .file_ack(1'b0), .file_data(8'd0), .file_error(1'b0), .sw_cdrom_ctrl(2'b11),
        .kernel_ok(kernel_ok), .halt_code(halt_code), .halt_part(halt_part), .pc_out(pc_out),
        .opcode_out(opcode_out), .dbg_in(16'd0), .dbg(dbg), .dbg2(dbg2), .dbg_cpu(dbg_cpu),
        .gpu_drawing(gpu_drawing), .sio_waiting(sio_waiting), .mdec_waiting(mdec_waiting),
        .vraming(vraming), .dma_running(dma_running), .dbg_cdr(dbg_cdr), .dbg_gpu(dbg_gpu),
        .dbg16(dbg16), .dbg32(dbg32), .dbg_pad(dbg_pad));

    // ---------------- memories ----------------
    reg [15:0] wram [0:1048575];
    reg [15:0] bios [0:262143];
    reg [15:0] vram [0:524287];
    reg [15:0] spuram [0:262143];

    // ---------------- SDRAM model ----------------
    integer lat_cfg = 6;
    localparam K_NONE = 0, K_WR = 1, K_BR = 2, K_WW = 3, K_VR = 4, K_VW = 5;
    integer kind = K_NONE, cnt = 0;
    reg gpu_rd_wait = 0, gpu_wr_wait = 0;
    reg [20:0] opA; reg [4:0] opW; reg [31:0] opD; reg [18:0] opV; reg [3:0] opB; reg [15:0] opVD;
    longint collisions = 0, ops = 0;
    wire cpu_req = WRAM_READ | BIOS_READ | WRAM_WRITE;
    // VRAM requests are issued only when ready and no GPU wait is pending (core.sflp:302-314).
    wire vram_go = !cpu_req && sdram_ack && !gpu_rd_wait && !gpu_wr_wait && (vram_read_req || vram_write_req);
    wire busy = kind != K_NONE;
    wire accept = !busy && (cpu_req || vram_go);

    function automatic [127:0] burst_read(input integer which, input integer base, input integer n);
        integer i; reg [127:0] r;
        begin r = 0;
            for (i = 0; i < 8; i++) if (i < n)
                r[16*i +: 16] = which == 0 ? wram[(base + i) & 20'hFFFFF] :
                                which == 1 ? bios[(base + i) & 18'h3FFFF] : vram[(base + i) & 19'h7FFFF];
            burst_read = r;
        end
    endfunction

    always @(posedge clk) begin
        vram_read_ack <= 0; vram_write_ack <= 0;
        // core-side registered ready (core.sflp:112) and the pending-GPU acks (333-341)
        sdram_ack <= !busy && !accept;
        if (gpu_rd_wait && sdram_ack) begin vram_read_ack <= 1; gpu_rd_wait <= 0; end
        if (gpu_wr_wait && sdram_ack) begin vram_write_ack <= 1; gpu_wr_wait <= 0; end
        if (busy && cpu_req) collisions++;
        if (accept) begin
            ops++; cnt <= lat_cfg;
            if (WRAM_READ) begin kind <= K_WR; opA <= A; opW <= Word; last_A <= A; last_Word <= Word; end
            else if (BIOS_READ) begin kind <= K_BR; opA <= A; opW <= Word; last_A <= A; last_Word <= Word; end
            else if (WRAM_WRITE) begin kind <= K_WW; opA <= A; opW <= Word; opD <= Dout; end
            else if (vram_read_req) begin kind <= K_VR; opV <= vram_adrs; opB <= {1'b0, vram_burst}; gpu_rd_wait <= 1; end
            else begin kind <= K_VW; opV <= vram_adrs; opVD <= vram_write_data; gpu_wr_wait <= 1; end
        end else if (busy) begin
            if (cnt > 0) cnt <= cnt - 1;
            else begin
                case (kind)
                    K_WR: sdram_dout <= (opW == 1 || opW == 2) ? burst_read(0, opA[20:1], 1)
                                                               : burst_read(0, {opA[20:2], 1'b0}, opW[4:1]);
                    K_BR: sdram_dout <= (opW == 1 || opW == 2) ? burst_read(1, opA[18:1], 1)
                                                               : burst_read(1, {opA[18:2], 1'b0}, 2);
                    K_WW: begin
                        if (opW == 1) begin
                            if (!opA[0]) wram[opA[20:1]][7:0] <= opD[7:0];
                            else         wram[opA[20:1]][15:8] <= opD[7:0];
                        end else if (opW == 2) wram[opA[20:1]] <= opD[15:0];
                        else begin wram[{opA[20:2], 1'b0}] <= opD[15:0]; wram[{opA[20:2], 1'b1}] <= opD[31:16]; end
                    end
                    K_VR: sdram_dout <= burst_read(2, opV, opB);
                    K_VW: vram[opV] <= opVD;
                    default: ;
                endcase
                kind <= K_NONE;
            end
        end
    end

    // ---------------- SPU RAM model ----------------
    integer spu_cnt = -1; reg [17:0] spu_opA; reg spu_isw; reg [15:0] spu_wd;
    always @(posedge clk) begin
        spu_ack <= 0;
        if (spu_cnt < 0 && (spu_rreq || spu_wreq) && !spu_ack) begin spu_cnt <= 4; spu_opA <= spu_A; spu_isw <= spu_wreq; spu_wd <= spu_Din; end
        else if (spu_cnt > 0) spu_cnt <= spu_cnt - 1;
        else if (spu_cnt == 0) begin
            spu_ack <= 1; spu_Dout <= spuram[spu_opA];
            if (spu_isw) spuram[spu_opA] <= spu_wd;
            spu_cnt <= -1;
        end
    end

    // ---------------- clocks: run33 DDS, vblank ----------------
    longint acc = 0, cyc = 0;
    localparam longint FRAME = 833333;   // 60 Hz at 50 MHz
    longint fcount = 0; integer frames = 0;
    always @(posedge clk) if (!reset) begin
        cyc++;
        if (acc + 33868800 >= 50000000) begin acc <= acc + 33868800 - 50000000; run33 <= 1; end
        else begin acc <= acc + 33868800; run33 <= 0; end
        vblank_begin <= 0; vblank_end <= 0;
        fcount <= fcount + 1;
        if (fcount == FRAME - 1) begin
            fcount <= 0; frames <= frames + 1;
            if (!gpu_drawing && !sio_waiting) vblank_begin <= 1;   // core.sflp:180-181
        end
        if (fcount == FRAME / 13) vblank_end <= 1;                  // ~20 of 263 lines
    end

    // ---------------- display capture ----------------
    reg [23:0] fb [0:239][0:319];
    longint pixel_writes = 0;
    always @(posedge clk) if (view_on) begin
        automatic int x = dispW ? view_x[9:1] : view_x[8:0];
        automatic int y = dispH ? view_y[8:1] : view_y[7:0];
        if (x < 320 && y < 240) fb[y][x] <= {view_R, view_G, view_B};
        pixel_writes++;
    end

    string outdir;
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

    // ---------------- run control ----------------
    string bios_file;
    longint max_cycles = 200000000;
    integer frames_every = 30, last_dumped = -1, kernel_seen = 0;
    initial begin
        integer x, y;
        if (!$value$plusargs("bios=%s", bios_file)) begin $display("FAIL: +bios=<hexfile> required"); $finish; end
        if (!$value$plusargs("outdir=%s", outdir)) outdir = ".";
        void'($value$plusargs("cycles=%d", max_cycles));
        void'($value$plusargs("frames_every=%d", frames_every));
        void'($value$plusargs("lat=%d", lat_cfg));
        for (x = 0; x < 1048576; x++) wram[x] = 0;
        for (x = 0; x < 524288; x++) vram[x] = 0;
        for (x = 0; x < 262144; x++) spuram[x] = 0;
        for (y = 0; y < 240; y++) for (x = 0; x < 320; x++) fb[y][x] = 0;
        $readmemh(bios_file, bios);
        $display("BIOS loaded: first words %h %h", bios[1], bios[0]);
        repeat (8) @(posedge clk); reset = 0;
        repeat (8) @(posedge clk); cpu_run = 1;
    end

    always @(posedge clk) if (!reset) begin
        if (kernel_ok && !kernel_seen) begin kernel_seen = 1; $display("KERNEL_OK cycle=%0d pc=%h", cyc, pc_out); end
        if (frames != last_dumped && frames % frames_every == 0) begin
            last_dumped = frames;
            dump_frame(frames);
            $display("FRAME %0d cycle=%0d pc=%h pixel_writes=%0d ops=%0d collisions=%0d halt=%h",
                     frames, cyc, pc_out, pixel_writes, ops, collisions, halt_code);
        end
        if (halt_code != 0) begin
            $display("HALT code=%h part=%h pc=%h opcode=%h cycle=%0d", halt_code, halt_part, pc_out, opcode_out, cyc);
            dump_frame(99999); $finish;
        end
        if (cyc >= max_cycles) begin
            dump_frame(frames);
            $display("END cycles=%0d frames=%0d pc=%h pixel_writes=%0d kernel_ok=%0d", cyc, frames, pc_out, pixel_writes, kernel_seen);
            $finish;
        end
    end
endmodule
