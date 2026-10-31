// SDR SDRAM controller for the Pocket's AS4C32M16 (64 MiB, 4 banks x 8192
// rows x 1024 columns x 16 bits) behind sdr_phy (half rate: one 32-bit word
// = one BL2 burst = one sys cycle of data).
//
// Requests are single 32-bit words, taken in order; reads come back in the
// order taken (rd_tag: what the requester passed with it). Open page per bank;
// at most one command per sys cycle, on phase 0 -- a stream of row hits is a
// word per cycle, reads and writes alike. The init sequence is the standard
// SDR SDRAM one (precharge all, refreshes, mode register), in hardware:
// nothing needs software to bring the SDRAM up. `ready` rises when it is done.
//
// Word address: row = a[23:11], bank = a[10:9], column pair = a[8:0].
// Timings in sys cycles at 62.832 MHz (15.9 ns; commands 2 sys2x apart):
// tRCD 18 ns, tRP 18 ns -> 2; tRAS 48 ns -> 4; tRFC 80 ns -> 6; tWR 15 ns
// after the second beat -> 2 from the WRITE; read -> write 3 (the burst's DQ
// window on the pads is sys2x +3/+4 after READ; a WRITE drives DQ at once);
// write -> read 2 (tWTR); tREFI 7.8 us -> refresh every T_REFI cycles.
//
// Phase 1 carries the row of the request to come (`la_*`, from the arbiter):
// a PRECHARGE and then an ACTIVATE of its bank, while phase 0 goes on with
// the request under way in another. A port's first word then finds its row
// open instead of holding every other port for the four cycles of opening
// it. Left alone: the bank of the request under way, and a bank read or
// written in the last T_IDLE cycles (a row the stream under way is still
// using: closing it would cost that stream the same four cycles). The same
// counts in sys cycles hold from either phase to either (the shortest, phase
// 1 to phase 0, is 2n - 1 sys2x: 24 ns for 2, 56 ns for tRAS's 4); two
// ACTIVATEs are kept 2 sys2x apart (tRRD).
`default_nettype none

module sdr_ctrl #(
    parameter int T_INIT = 12600,       // 200 us of power-up wait
    parameter int T_REFI = 480,
    parameter int T_RFC  = 6,
    parameter int T_RP   = 2,
    parameter int T_RCD  = 2,
    parameter int T_RAS  = 4,
    parameter int T_WR   = 2,
    parameter int T_R2W  = 3,
    parameter int T_W2R  = 2,
    parameter int T_MRD  = 3,
    parameter int T_IDLE = 6,
    parameter bit AHEAD  = 1,           // phase 1's row opening (0: as before it)
    parameter int RL     = 5,           // sys cycles from rddata_en to the word on dfi_rddata (sdr_phy)
    parameter int TAGW   = 3
) (
    input  wire              clk,
    input  wire              rst,
    output logic             ready,          // the init sequence is done
    // requests: held until req_ready
    input  wire              req_valid,
    input  wire              req_we,
    input  wire  [23:0]      req_addr,       // 32-bit word address
    input  wire  [31:0]      req_wdata,
    input  wire  [3:0]       req_be,         // byte enables (writes)
    input  wire  [TAGW-1:0]  req_tag,
    output logic             req_ready,
    // the request to come (a hint: its row is opened ahead)
    input  wire              la_valid,
    input  wire  [23:0]      la_addr,
    // read data, in request order
    output logic             rd_valid,
    output logic [31:0]      rd_data,
    output logic [TAGW-1:0]  rd_tag,
    output logic             rd_next,        // rd_valid and rd_tag as they will be in the next cycle
    output logic [TAGW-1:0]  rd_next_tag,
    // to sdr_phy (DFI, two phases; phase 1: a PRECHARGE or an ACTIVATE, or NOP)
    output logic [1:0]       dfi_ras_n, dfi_cas_n, dfi_we_n,
    output logic [25:0]      dfi_addr,
    output logic [3:0]       dfi_ba,
    output logic             dfi_cke,
    output logic             dfi_wrdata_en,
    output logic [31:0]      dfi_wrdata,
    output logic [3:0]       dfi_wrdata_mask,
    output logic             dfi_rddata_en,
    input  wire  [31:0]      dfi_rddata,
    input  wire              dfi_rddata_valid
);

// ---- command encodings {ras_n, cas_n, we_n}
localparam logic [2:0] C_NOP = 3'b111, C_ACT = 3'b011, C_RD = 3'b101, C_WR = 3'b100,
                       C_PRE = 3'b010, C_REF = 3'b001, C_MRS = 3'b000;

// the command issued this cycle (phase 0)
logic [2:0]  cmd;
logic [12:0] cmd_a;
logic [1:0]  cmd_ba;
logic        cmd_wr, cmd_rd;
// and phase 1's
logic [2:0]  cmd1;
logic [12:0] cmd1_a;
logic [1:0]  cmd1_ba;
always_comb begin
    dfi_ras_n = {cmd1[2], cmd[2]}; dfi_cas_n = {cmd1[1], cmd[1]}; dfi_we_n = {cmd1[0], cmd[0]};
    dfi_addr = {cmd1_a, cmd_a}; dfi_ba = {cmd1_ba, cmd_ba};
    dfi_wrdata_en = cmd_wr; dfi_wrdata = req_wdata; dfi_wrdata_mask = ~req_be;
    dfi_rddata_en = cmd_rd;
end

// ---- the request's place
wire [12:0] q_row  = req_addr[23:11];
wire [1:0]  q_bank = req_addr[10:9];
wire [9:0]  q_col  = {req_addr[8:0], 1'b0};

// ---- bank state and timers (saturating counts of cycles since the event)
logic [3:0]  open;
logic [12:0] row [4];
logic [3:0]  c_act [4], c_pre [4], c_wr [4];
logic [3:0]  c_rd, c_wrany;
logic [3:0]  c_use [4];             // since a READ or a WRITE there
logic        act1_d;                // phase 1 of the last cycle was an ACTIVATE
wire [12:0] l_row  = la_addr[23:11];
wire [1:0]  l_bank = la_addr[10:9];
function automatic logic [3:0] sat(input logic [3:0] v); return v == 4'hF ? v : v + 4'd1; endfunction

// ---- init / refresh sequencing
typedef enum logic [3:0] { S_POWER, S_PRE1, S_MRS1, S_PRE2, S_REF1, S_REF2, S_MRS2, S_RUN,
                           S_RPRE, S_RREF } st_t;
st_t st;
logic [13:0] wait_c;                // cycles left before the next init/refresh step
logic [9:0]  refi_c;
logic        ref_due;
wire         all_closable = (!open[0] || (c_act[0] >= T_RAS && c_wr[0] >= T_WR))
                         && (!open[1] || (c_act[1] >= T_RAS && c_wr[1] >= T_WR))
                         && (!open[2] || (c_act[2] >= T_RAS && c_wr[2] >= T_WR))
                         && (!open[3] || (c_act[3] >= T_RAS && c_wr[3] >= T_WR));

// ---- this cycle's decision
always_comb begin
    cmd = C_NOP; cmd_a = '0; cmd_ba = '0; cmd_wr = 0; cmd_rd = 0; req_ready = 0;
    if (wait_c == 0) case (st)
    S_PRE1, S_PRE2:  begin cmd = C_PRE; cmd_a = 13'h400; end
    S_MRS1:          begin cmd = C_MRS; cmd_a = 13'h131; end        // (the BIOS's: CL 3, BL 2, "reset DLL")
    S_MRS2:          begin cmd = C_MRS; cmd_a = 13'h031; end        // CL 3, BL 2
    S_REF1, S_REF2:  cmd = C_REF;
    S_RPRE:          if (all_closable) begin cmd = C_PRE; cmd_a = 13'h400; end
    S_RREF:          cmd = C_REF;
    S_RUN: if (!ref_due && req_valid) begin
        if (open[q_bank] && row[q_bank] == q_row) begin
            if (c_act[q_bank] >= T_RCD && (req_we ? c_rd >= T_R2W : c_wrany >= T_W2R)) begin
                cmd = req_we ? C_WR : C_RD; cmd_a = {3'd0, q_col}; cmd_ba = q_bank;
                cmd_wr = req_we; cmd_rd = !req_we; req_ready = 1;
            end
        end else if (open[q_bank]) begin
            if (c_act[q_bank] >= T_RAS && c_wr[q_bank] >= T_WR) begin cmd = C_PRE; cmd_ba = q_bank; end
        end else if (c_pre[q_bank] >= T_RP && !act1_d) begin
            cmd = C_ACT; cmd_a = q_row; cmd_ba = q_bank;
        end
    end
    default: ;
    endcase
end
always_comb begin
    cmd1 = C_NOP; cmd1_a = '0; cmd1_ba = l_bank;
    if (AHEAD && st == S_RUN && wait_c == 0 && !ref_due && la_valid && !(req_valid && q_bank == l_bank)) begin
        if (open[l_bank]) begin
            if (row[l_bank] != l_row && c_use[l_bank] >= T_IDLE && c_act[l_bank] >= T_RAS && c_wr[l_bank] >= T_WR) cmd1 = C_PRE;
        end else if (c_pre[l_bank] >= T_RP && cmd != C_ACT) begin
            cmd1 = C_ACT; cmd1_a = l_row;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        st <= S_POWER; wait_c <= 14'(T_INIT); refi_c <= '0; ref_due <= 0; ready <= 0; dfi_cke <= 0;
        open <= '0; c_rd <= '1; c_wrany <= '1; act1_d <= 0;
        for (int b = 0; b < 4; b++) begin c_act[b] <= '1; c_pre[b] <= '1; c_wr[b] <= '1; c_use[b] <= '1; row[b] <= '0; end
    end else begin
        dfi_cke <= 1;
        // timers
        c_rd <= cmd == C_RD ? 4'd1 : sat(c_rd);
        c_wrany <= cmd == C_WR ? 4'd1 : sat(c_wrany);
        for (int b = 0; b < 4; b++) begin
            c_act[b] <= ((cmd == C_ACT && cmd_ba == 2'(b)) || (cmd1 == C_ACT && cmd1_ba == 2'(b))) ? 4'd1 : sat(c_act[b]);
            c_pre[b] <= ((cmd == C_PRE && (cmd_ba == 2'(b) || cmd_a[10])) || (cmd1 == C_PRE && cmd1_ba == 2'(b))) ? 4'd1 : sat(c_pre[b]);
            c_wr[b]  <= (cmd == C_WR && cmd_ba == 2'(b)) ? 4'd1 : sat(c_wr[b]);
            c_use[b] <= ((cmd == C_WR || cmd == C_RD) && cmd_ba == 2'(b)) ? 4'd1 : sat(c_use[b]);
        end
        act1_d <= cmd1 == C_ACT;
        // bank state (the two phases are never of one bank)
        if (cmd == C_ACT) begin open[cmd_ba] <= 1; row[cmd_ba] <= cmd_a; end
        if (cmd == C_PRE) begin if (cmd_a[10]) open <= '0; else open[cmd_ba] <= 0; end
        if (cmd1 == C_ACT) begin open[cmd1_ba] <= 1; row[cmd1_ba] <= cmd1_a; end
        if (cmd1 == C_PRE) open[cmd1_ba] <= 0;
        // refresh interval
        if (st != S_RUN && st != S_RPRE && st != S_RREF) refi_c <= '0;
        else if (refi_c == 10'(T_REFI - 1)) begin refi_c <= '0; ref_due <= 1; end
        else refi_c <= refi_c + 10'd1;
        // sequencing
        if (wait_c != 0) wait_c <= wait_c - 14'd1;
        else case (st)
        S_POWER: st <= S_PRE1;
        S_PRE1:  begin st <= S_MRS1; wait_c <= 14'(T_RP); end
        S_MRS1:  begin st <= S_PRE2; wait_c <= 14'(T_MRD); end
        S_PRE2:  begin st <= S_REF1; wait_c <= 14'(T_RP); end
        S_REF1:  begin st <= S_REF2; wait_c <= 14'(T_RFC); end
        S_REF2:  begin st <= S_MRS2; wait_c <= 14'(T_RFC); end
        S_MRS2:  begin st <= S_RUN;  wait_c <= 14'(T_MRD); ready <= 1; end
        S_RUN:   if (ref_due && !(cmd == C_RD || cmd == C_WR)) st <= S_RPRE;
        S_RPRE:  if (cmd == C_PRE) begin st <= S_RREF; wait_c <= 14'(T_RP); end
        S_RREF:  begin st <= S_RUN; wait_c <= 14'(T_RFC); ref_due <= 0; end
        default: st <= S_POWER;
        endcase
    end
end

// ---- read data: RL cycles after the READ (the PHY's own valid is a sys2x
// pulse that sys does not see -- LiteDRAM timed reads the same way)
logic [RL-1:0]   rd_sr;
logic [TAGW-1:0] tag_sr [RL];
always_ff @(posedge clk) begin
    if (rst) rd_sr <= '0;
    else rd_sr <= {rd_sr[RL-2:0], cmd_rd};
    tag_sr[0] <= req_tag;
    for (int i = 1; i < RL; i++) tag_sr[i] <= tag_sr[i - 1];
end
assign rd_valid = rd_sr[RL-1];
assign rd_data  = dfi_rddata;
assign rd_tag   = tag_sr[RL-1];
assign rd_next  = rd_sr[RL-2];
assign rd_next_tag = tag_sr[RL-2];

endmodule
`default_nettype wire
