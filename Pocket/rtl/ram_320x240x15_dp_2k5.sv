// SPDX-License-Identifier: MIT
// Q-L1-16: ram_320x240x15_dp (Pocket/rtl/ram_320x240x15_dp.sv) with the same ports and
// behaviour, as an explicit altsyncram with maximum_depth 2048, so it is built from 2K x 5
// M10K slices: 38 x 3 = 114 blocks instead of the 144 of the default packing. Two view
// buffers then fit next to the core (2 x 114 + 26 of 308 blocks); the cost is a wider read
// mux. An inferred RAM with a max_depth attribute is not enough: Analysis & Synthesis
// budgets inferred RAMs with its own block estimate, ran out with two view buffers and left
// 11 of the core's RAMs as logic (r15, r18: 40k ALMs).
// Registered read: dout shows the word addressed in the previous cycle with rd_en.
`default_nettype none

module ram_320x240x15_dp_2k5 (
    input  wire         clk,
    input  wire         wr_en,
    input  wire [16:0]  wr_adrs,
    input  wire [14:0]  wr_data,
    input  wire         rd_en,
    input  wire [16:0]  rd_adrs,
    output logic [14:0] dout
);
    localparam integer DEPTH = 320 * 240;
`ifdef VERILATOR
    logic [14:0] mem [0:DEPTH-1];
    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_adrs] <= wr_data;
        if (rd_en)
            dout <= mem[rd_adrs];
    end
`else
    altsyncram #(
        .operation_mode("DUAL_PORT"),
        .intended_device_family("Cyclone V"),
        .ram_block_type("M10K"),
        .maximum_depth(2048),
        .width_a(15), .widthad_a(17), .numwords_a(DEPTH),
        .width_b(15), .widthad_b(17), .numwords_b(DEPTH),
        .width_byteena_a(1),
        .address_reg_b("CLOCK0"),
        .rdcontrol_reg_b("CLOCK0"),
        .outdata_reg_b("UNREGISTERED"),
        .outdata_aclr_b("NONE"),
        .address_aclr_b("NONE"),
        .clock_enable_input_a("BYPASS"),
        .clock_enable_input_b("BYPASS"),
        .clock_enable_output_b("BYPASS"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized("FALSE"),
        .lpm_type("altsyncram")
    ) u_mem (
        .clock0(clk),
        .wren_a(wr_en), .address_a(wr_adrs), .data_a(wr_data),
        .rden_b(rd_en), .address_b(rd_adrs), .q_b(dout),
        .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0),
        .byteena_a(1'b1), .byteena_b(1'b1), .clock1(1'b1), .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1), .data_b({15{1'b1}}), .eccstatus(), .q_a(),
        .rden_a(1'b1), .wren_b(1'b0)
    );
`endif
endmodule

`default_nettype wire
