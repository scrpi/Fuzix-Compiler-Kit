// cc — the condition-code board: the CC register (cc_register) plus the microcondition
// generation (cc_conditions). Structural (R-SIM-1, R-SIM-5; isa.md §8; the CC board of
// cpu-physical-construction.md §5). Latches the ALU flags under microcode control and exports
// CC.M (to SP-bank/MMU/sequencer) and the CC-derived branch conditions to the microsequencer.
`timescale 1ns/1ps
`default_nettype none
module cc (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        flag_n, flag_z, flag_v, flag_c, flag_h,
    input  wire [4:0]  flag_we,
    input  wire [3:0]  v_src_n,
    input  wire [3:0]  c_src_n,
    input  wire        z_accum,
    input  wire [3:0]  cc_write_n,
    input  wire [3:0]  cc_mi_n,
    input  wire [7:0]  z_lo,
    output wire [7:0]  cc_q,
    output wire        cc_m,
    output wire [6:0]  cond          // CC-derived microconditions (sequencer cond[6:0])
);
    (* purpose = "CC register + write logic" *)
    cc_register u_reg (
        .clk(clk), .reset_n(reset_n),
        .flag_n(flag_n), .flag_z(flag_z), .flag_v(flag_v), .flag_c(flag_c), .flag_h(flag_h),
        .flag_we(flag_we), .v_src_n(v_src_n), .c_src_n(c_src_n), .z_accum(z_accum),
        .cc_write_n(cc_write_n), .cc_mi_n(cc_mi_n), .z_lo(z_lo),
        .cc_q(cc_q), .cc_m(cc_m)
    );
    (* purpose = "CC condition generation" *)
    cc_conditions u_cond (.cc_q(cc_q), .cond(cond));
endmodule
`default_nettype wire
