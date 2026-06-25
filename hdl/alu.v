// alu — the 16-bit ALU: the result bus and flag selection over three functional sections
// (alu_arithmetic, alu_logic, alu_shift). Structural netlist (R-SIM-1, R-SIM-5; hardware.md
// §2, §9.2; R-CTRL-4). One ALU does data, pointer, and EA math.
//
// Operands LEFT and RIGHT (the asymmetric source buses); the result drives the Z bus. The op
// is the decoded one-hot ALU_OP: each section tri-states its result onto the SHARED `z` bus
// (a wired-OR result mux), and this top adds the PASS_L/PASS_R register-move drivers. Exactly
// one driver is enabled at a time (ALU_OP is one-hot), so the bus carries the selected result.
//
// Flags: N and Z are taken from the result bus (so they are correct for whichever section
// drove it); C and V come from the arithmetic section, except on a SHIFT op when they are
// taken from the shift section's carry-out and overflow; H is the arithmetic half-carry.
// These are the ALU's COMPUTED flags — FLAG_WE/V_SRC/C_SRC on the CC board gate what lands.
//
//   sections:  alu_arithmetic  ADD/ADC/SUB/SBC/NEG (+ V, borrow-C, H)
//              alu_logic       AND/OR/EOR/COM
//              alu_shift       ASL/LSR/ASR/ROL/ROR (+ shift carry/V)
//   here:      PASS_L/PASS_R drivers, the Z-reduction (N/Z), and the flag selection.
`timescale 1ns/1ps
`default_nettype none
module alu (
    input  wire [15:0] left,
    input  wire [15:0] right,
    input  wire [15:0] alu_op_n,    // decoded ALU_OP one-hot, active LOW (control_word_decoder)
    input  wire [7:0]  alu_shift_n, // decoded ALU_SHIFT one-hot, active LOW
    input  wire        alu_cin,     // ALU_CIN literal: 0=ZERO, 1=CC_C
    input  wire        alu_width,   // ALU_WIDTH: 0=W8, 1=W16
    input  wire        cc_c,        // current CC.C (carry-in for ADC/SBC and ALU_CIN=CC_C)
    output wire [15:0] z,           // ALU result -> Z bus (shared, tri-state)
    output wire        flag_n,      // sign (active-width MSB of the result)
    output wire        flag_z,      // result == 0 over the active width
    output wire        flag_v,      // signed overflow (arith) / shift overflow
    output wire        flag_c,      // carry/borrow (arith) / shift carry
    output wire        flag_h       // half-carry: carry into bit 4
);
    // ---- PASS_L / PASS_R: register moves drive LEFT/RIGHT straight onto the result bus ----
    (* purpose = "Z<-LEFT  (PASS_L) [7:0]" *)  sn74ahct541 rl0 (.a(left[7:0]),   .oe1_n(alu_op_n[0]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-LEFT  [15:8]" *)          sn74ahct541 rl1 (.a(left[15:8]),  .oe1_n(alu_op_n[0]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-RIGHT (PASS_R) [7:0]" *)  sn74ahct541 rr0 (.a(right[7:0]),  .oe1_n(alu_op_n[1]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-RIGHT [15:8]" *)          sn74ahct541 rr1 (.a(right[15:8]), .oe1_n(alu_op_n[1]), .oe2_n(1'b0), .y(z[15:8]));

    // ---- the three functional sections, all driving the shared result bus ----------
    wire fc_arith, fv_arith;
    (* purpose = "arithmetic section" *)
    alu_arithmetic u_arith (
        .left(left), .right(right), .alu_op_n(alu_op_n), .alu_cin(alu_cin), .alu_width(alu_width),
        .cc_c(cc_c), .z(z), .flag_c_arith(fc_arith), .flag_v_arith(fv_arith), .flag_h(flag_h)
    );
    (* purpose = "logic section" *)
    alu_logic u_logic (.left(left), .right(right), .op_n(alu_op_n[9:6]), .z(z));
    wire shift_carry, shift_v, op_shift;
    (* purpose = "shift section" *)
    alu_shift u_shift (
        .left(left), .cc_c(cc_c), .alu_width(alu_width), .alu_shift_n(alu_shift_n),
        .op_shift_n(alu_op_n[11]), .z(z), .shift_carry(shift_carry), .shift_v(shift_v), .op_shift(op_shift)
    );

    // ---- N / Z from the result bus (correct for whichever section drove it) ---------
    // Z = NOR of the result over the active width (OR-reduce tree, distinct packages).
    wire [3:0] zr0, zr1, zr2;
    (* purpose = "Z-reduce pairs [7:0]" *)
    sn74ahct32 zl (.a({z[6], z[4], z[2], z[0]}), .b({z[7], z[5], z[3], z[1]}), .y(zr0));
    (* purpose = "Z-reduce pairs [15:8]" *)
    sn74ahct32 zh (.a({z[14], z[12], z[10], z[8]}), .b({z[15], z[13], z[11], z[9]}), .y(zr1));
    (* purpose = "Z-reduce quads" *)
    sn74ahct32 zq (.a({zr1[2], zr1[0], zr0[2], zr0[0]}), .b({zr1[3], zr1[1], zr0[3], zr0[1]}), .y(zr2));
    wire [3:0] zhalf;
    (* purpose = "Z-reduce halves" *)
    sn74ahct32 zf (.a({2'b0, zr2[2], zr2[0]}), .b({2'b0, zr2[3], zr2[1]}), .y(zhalf));
    wire orlo = zhalf[0], orhi = zhalf[1];
    wire [3:0] zall;
    (* purpose = "Z-reduce all" *)
    sn74ahct32 za (.a({3'b0, orlo}), .b({3'b0, orhi}), .y(zall));
    wire [5:0] zinv;
    (* purpose = "Z8=~orlo, Z16=~orall" *)
    sn74ahct04 zn (.a({4'b0, zall[0], orlo}), .y(zinv));
    wire z8 = zinv[0], z16 = zinv[1];

    wire [3:0] nzf;
    (* purpose = "N/Z width mux" *)
    sn74ahct157 nzmux (.a({2'b0, z8, z[7]}), .b({2'b0, z16, z[15]}), .sel(alu_width), .g_n(1'b0), .y(nzf));
    assign flag_n = nzf[0];
    assign flag_z = nzf[1];

    // ---- C / V: arithmetic, overridden by the shift section on a SHIFT op ----------
    wire [3:0] cvf;
    (* purpose = "C/V arith-vs-shift mux" *)
    sn74ahct157 cvmux (.a({2'b0, fv_arith, fc_arith}), .b({2'b0, shift_v, shift_carry}), .sel(op_shift), .g_n(1'b0), .y(cvf));
    assign flag_c = cvf[0];
    assign flag_v = cvf[1];
endmodule
`default_nettype wire
