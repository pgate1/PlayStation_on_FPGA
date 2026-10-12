// SIMULATION/LINT ONLY. Interface declarations copied from the pinned APF
// template; these modules have no PLL or memory behavior and must never be
// added to a Quartus project or QSF.
(* blackbox *) module mf_pllbase (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire outclk_2,
    output wire outclk_3,
    output wire outclk_4,
    output wire locked
);
endmodule

(* blackbox *) module mf_datatable (
    input  wire [7:0]  address_a,
    input  wire [7:0]  address_b,
    input  wire        clock_a,
    input  wire        clock_b,
    input  wire [31:0] data_a,
    input  wire [31:0] data_b,
    input  wire        wren_a,
    input  wire        wren_b,
    output wire [31:0] q_a,
    output wire [31:0] q_b
);
endmodule
