// alu — the 16-bit ALU compute core (arithmetic + logic + moves), with N/Z/V/C/H flag
// generation. Structural netlist of real chips (R-SIM-1, R-SIM-5; hardware.md §2, §9.2
// "discrete adders + logic-op mux"; R-CTRL-4). One ALU does data, pointer, and EA math.
//
// Operands: LEFT and RIGHT (the asymmetric source buses, hardware.md §2); the result drives
// the Z bus. The op is selected by the decoded one-hot ALU_OP strobes; the result reaches Z
// through per-op tri-state drivers (a wired-OR result mux — the bus-oriented analogue of the
// "decode centrally, one-hot enable a driver" pattern used throughout the datapath).
//
//   PASS_L/PASS_R  — Z = LEFT / RIGHT (register moves are ALU pass-throughs)
//   ADD/ADC        — Z = LEFT + RIGHT (+C for ADC; +C for ADD when ALU_CIN=CC_C)
//   SUB/SBC        — Z = LEFT - RIGHT (- ~C for SBC) via LEFT + ~RIGHT + cin
//   NEG            — Z = -LEFT = ~LEFT + 1
//   AND/OR/EOR     — bitwise ; COM — Z = ~LEFT
//
// Subtraction is two's-complement add: RIGHT is XOR-inverted (binv) for SUB/SBC/NEG and the
// carry-in supplies the +1. The carry flag follows the BORROW convention on subtracts
// (C = carry_out XOR binv): C=1 means borrow (LEFT < RIGHT unsigned), so BLS/BCS work.
// Overflow V = A_msb ^ B_msb ^ S_msb ^ carry_out (= carry-in_msb ^ carry-out_msb) on the
// post-inversion adder inputs, valid for add and subtract. Half-carry H = carry into bit4.
// Width: W8 takes N/Z/V/C from the 8-bit boundary (bit7 / carry-out of bit7), W16 from bit15.
//
// Flags here are the ALU's COMPUTED flags; what actually lands in CC is gated by FLAG_WE and
// overridden by V_SRC/C_SRC on the CC board (so logic ops force V=0 etc. there, not here).
//
// Structure (the BOM): 4x sn74f283 (adder); sn74ahct08/32/86/04 (logic + control glue);
// 14x sn74ahct541 (7-source tri-state result mux); 1x sn74ahct157 (width flag mux).
//
// SCAFFOLD: SHIFT (ALU_OP=11, qualified by ALU_SHIFT) is the next increment — its result
// driver and shift-carry path are not wired yet, so a SHIFT microword leaves Z undriven.
`timescale 1ns/1ps
`default_nettype none
module alu (
    input  wire [15:0] left,
    input  wire [15:0] right,
    input  wire [15:0] alu_op_n,    // decoded ALU_OP one-hot, active LOW (control_word_decoder)
    input  wire        alu_cin,     // ALU_CIN literal: 0=ZERO, 1=CC_C
    input  wire        alu_width,   // ALU_WIDTH: 0=W8, 1=W16
    input  wire        cc_c,        // current CC.C (carry-in for ADC/SBC and ALU_CIN=CC_C)
    output wire [15:0] z,           // ALU result -> Z bus
    output wire        flag_n,      // sign (active-width MSB of the result)
    output wire        flag_z,      // result == 0 over the active width
    output wire        flag_v,      // signed overflow (arithmetic)
    output wire        flag_c,      // carry (ADD) / borrow (SUB) out, per width
    output wire        flag_h       // half-carry: carry into bit 4
);
    // ---- op strobes -> active-high senses ------------------------------------------
    wire [5:0] op;                  // [0]=ADD [1]=ADC [2]=SUB [3]=SBC [4]=NEG
    (* purpose = "ALU arith op senses" *)
    sn74ahct04 ops (.a({1'b0, alu_op_n[10], alu_op_n[5], alu_op_n[4], alu_op_n[3], alu_op_n[2]}), .y(op));
    wire op_add = op[0], op_adc = op[1], op_sub = op[2], op_sbc = op[3], op_neg = op[4];

    // ---- control glue. Every chained gate crosses package boundaries: a single cell's
    // `assign y = a OP b` is one atomic vector op, so a package output must never feed that
    // same package's input (it would not settle). Levels below are in distinct packages.
    //   L1: ga=SUB|SBC  force1=SUB|NEG  gb=ADC|SBC    p_addcin=ADD&ALU_CIN
    //   L2: binv=ga|NEG  usec=gb|p_addcin  or_ab=ADD|gb
    //   L3: cin=force1|p_usec_c  arith_active=or_ab|force1  (+ Z halves)  p_usec_c=usec&CC.C
    wire [3:0] or1;
    (* purpose = "L1 OR: ga/force1/gb" *)
    sn74ahct32 orp1 (.a({1'b0, op_adc, op_sub, op_sub}), .b({1'b0, op_sbc, op_neg, op_sbc}), .y(or1));
    wire ga = or1[0], force1 = or1[1], gb = or1[2];

    wire [3:0] a1;
    (* purpose = "L1 AND: ADD&ALU_CIN" *)
    sn74ahct08 andp1 (.a({3'b0, op_add}), .b({3'b0, alu_cin}), .y(a1));
    wire p_addcin = a1[0];

    wire [3:0] or2;
    (* purpose = "L2 OR: binv/usec/or_ab" *)
    sn74ahct32 orp2 (.a({1'b0, op_add, gb, ga}), .b({1'b0, gb, p_addcin, op_neg}), .y(or2));
    wire binv = or2[0], usec = or2[1], or_ab = or2[2];

    wire [3:0] a2;
    (* purpose = "L2 AND: usec&CC.C" *)
    sn74ahct08 andp2 (.a({3'b0, usec}), .b({3'b0, cc_c}), .y(a2));
    wire p_usec_c = a2[0];

    // L3: cin = force1 | (usec & CC.C) ; arith_active = ADD|ADC|SUB|SBC|NEG (= or_ab|force1).
    wire [3:0] or3;
    (* purpose = "L3 OR: cin ; arith_active" *)
    sn74ahct32 orp3 (.a({2'b0, or_ab, force1}), .b({2'b0, force1, p_usec_c}), .y(or3));
    wire cin = or3[0], arith_active = or3[1];
    // arith driver enable is active-low: LOW when any arithmetic op is selected.
    wire [5:0] invE;
    (* purpose = "arith_en_n = ~arith_active" *)
    sn74ahct04 ie (.a({5'b0, arith_active}), .y(invE));
    wire arith_en_n = invE[0];

    // ---- adder operand conditioning ------------------------------------------------
    // A = NEG ? 0 : LEFT  (alu_op_n[10] is already ~op_neg, so AND-mask LEFT with it).
    // B = (NEG ? LEFT : RIGHT) XOR binv.
    wire [15:0] adderA, bpre, adderB;
    (* purpose = "A mask [3:0]" *)   sn74ahct08 mA0 (.a(left[3:0]),   .b({4{alu_op_n[10]}}), .y(adderA[3:0]));
    (* purpose = "A mask [7:4]" *)   sn74ahct08 mA1 (.a(left[7:4]),   .b({4{alu_op_n[10]}}), .y(adderA[7:4]));
    (* purpose = "A mask [11:8]" *)  sn74ahct08 mA2 (.a(left[11:8]),  .b({4{alu_op_n[10]}}), .y(adderA[11:8]));
    (* purpose = "A mask [15:12]" *) sn74ahct08 mA3 (.a(left[15:12]), .b({4{alu_op_n[10]}}), .y(adderA[15:12]));

    (* purpose = "Bpre [3:0]" *)   sn74ahct157 bp0 (.a(right[3:0]),   .b(left[3:0]),   .sel(op_neg), .g_n(1'b0), .y(bpre[3:0]));
    (* purpose = "Bpre [7:4]" *)   sn74ahct157 bp1 (.a(right[7:4]),   .b(left[7:4]),   .sel(op_neg), .g_n(1'b0), .y(bpre[7:4]));
    (* purpose = "Bpre [11:8]" *)  sn74ahct157 bp2 (.a(right[11:8]),  .b(left[11:8]),  .sel(op_neg), .g_n(1'b0), .y(bpre[11:8]));
    (* purpose = "Bpre [15:12]" *) sn74ahct157 bp3 (.a(right[15:12]), .b(left[15:12]), .sel(op_neg), .g_n(1'b0), .y(bpre[15:12]));

    (* purpose = "B = Bpre^binv [3:0]" *)   sn74ahct86 bx0 (.a(bpre[3:0]),   .b({4{binv}}), .y(adderB[3:0]));
    (* purpose = "B^binv [7:4]" *)   sn74ahct86 bx1 (.a(bpre[7:4]),   .b({4{binv}}), .y(adderB[7:4]));
    (* purpose = "B^binv [11:8]" *)  sn74ahct86 bx2 (.a(bpre[11:8]),  .b({4{binv}}), .y(adderB[11:8]));
    (* purpose = "B^binv [15:12]" *) sn74ahct86 bx3 (.a(bpre[15:12]), .b({4{binv}}), .y(adderB[15:12]));

    // ---- the adder: 4x '283, ripple carry; taps at bit3 (H), bit7 (C8), bit15 (C16) --
    wire [15:0] sum;
    wire c4, c8, c12, c16;
    (* purpose = "adder [3:0]" *)   sn74f283 add0 (.S(sum[3:0]),   .C4(c4),  .A(adderA[3:0]),   .B(adderB[3:0]),   .C0(cin));
    (* purpose = "adder [7:4]" *)   sn74f283 add1 (.S(sum[7:4]),   .C4(c8),  .A(adderA[7:4]),   .B(adderB[7:4]),   .C0(c4));
    (* purpose = "adder [11:8]" *)  sn74f283 add2 (.S(sum[11:8]),  .C4(c12), .A(adderA[11:8]),  .B(adderB[11:8]),  .C0(c8));
    (* purpose = "adder [15:12]" *) sn74f283 add3 (.S(sum[15:12]), .C4(c16), .A(adderA[15:12]), .B(adderB[15:12]), .C0(c12));

    // ---- logic ops -----------------------------------------------------------------
    wire [15:0] and_out, or_out, eor_out, com_out;
    (* purpose = "AND [3:0]" *)   sn74ahct08 an0 (.a(left[3:0]),   .b(right[3:0]),   .y(and_out[3:0]));
    (* purpose = "AND [7:4]" *)   sn74ahct08 an1 (.a(left[7:4]),   .b(right[7:4]),   .y(and_out[7:4]));
    (* purpose = "AND [11:8]" *)  sn74ahct08 an2 (.a(left[11:8]),  .b(right[11:8]),  .y(and_out[11:8]));
    (* purpose = "AND [15:12]" *) sn74ahct08 an3 (.a(left[15:12]), .b(right[15:12]), .y(and_out[15:12]));
    (* purpose = "OR [3:0]" *)    sn74ahct32 o0 (.a(left[3:0]),   .b(right[3:0]),   .y(or_out[3:0]));
    (* purpose = "OR [7:4]" *)    sn74ahct32 o1 (.a(left[7:4]),   .b(right[7:4]),   .y(or_out[7:4]));
    (* purpose = "OR [11:8]" *)   sn74ahct32 o2 (.a(left[11:8]),  .b(right[11:8]),  .y(or_out[11:8]));
    (* purpose = "OR [15:12]" *)  sn74ahct32 o3 (.a(left[15:12]), .b(right[15:12]), .y(or_out[15:12]));
    (* purpose = "EOR [3:0]" *)   sn74ahct86 e0 (.a(left[3:0]),   .b(right[3:0]),   .y(eor_out[3:0]));
    (* purpose = "EOR [7:4]" *)   sn74ahct86 e1 (.a(left[7:4]),   .b(right[7:4]),   .y(eor_out[7:4]));
    (* purpose = "EOR [11:8]" *)  sn74ahct86 e2 (.a(left[11:8]),  .b(right[11:8]),  .y(eor_out[11:8]));
    (* purpose = "EOR [15:12]" *) sn74ahct86 e3 (.a(left[15:12]), .b(right[15:12]), .y(eor_out[15:12]));
    (* purpose = "COM [3:0]" *)   sn74ahct86 c0 (.a(left[3:0]),   .b(4'hF), .y(com_out[3:0]));
    (* purpose = "COM [7:4]" *)   sn74ahct86 c1 (.a(left[7:4]),   .b(4'hF), .y(com_out[7:4]));
    (* purpose = "COM [11:8]" *)  sn74ahct86 c2 (.a(left[11:8]),  .b(4'hF), .y(com_out[11:8]));
    (* purpose = "COM [15:12]" *) sn74ahct86 c3 (.a(left[15:12]), .b(4'hF), .y(com_out[15:12]));

    // ---- result mux: 7 tri-state sources onto Z (one-hot, active-low enables) -------
    // (arith_en_n was formed above from arith_active.)
    (* purpose = "Z<-LEFT  [7:0]" *)  sn74ahct541 rl0 (.a(left[7:0]),    .oe1_n(alu_op_n[0]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-LEFT  [15:8]" *) sn74ahct541 rl1 (.a(left[15:8]),   .oe1_n(alu_op_n[0]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-RIGHT [7:0]" *)  sn74ahct541 rr0 (.a(right[7:0]),   .oe1_n(alu_op_n[1]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-RIGHT [15:8]" *) sn74ahct541 rr1 (.a(right[15:8]),  .oe1_n(alu_op_n[1]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-SUM [7:0]" *)    sn74ahct541 rs0 (.a(sum[7:0]),     .oe1_n(arith_en_n),  .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-SUM [15:8]" *)   sn74ahct541 rs1 (.a(sum[15:8]),    .oe1_n(arith_en_n),  .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-AND [7:0]" *)    sn74ahct541 ra0 (.a(and_out[7:0]), .oe1_n(alu_op_n[6]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-AND [15:8]" *)   sn74ahct541 ra1 (.a(and_out[15:8]),.oe1_n(alu_op_n[6]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-OR [7:0]" *)     sn74ahct541 ro0 (.a(or_out[7:0]),  .oe1_n(alu_op_n[7]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-OR [15:8]" *)    sn74ahct541 ro1 (.a(or_out[15:8]), .oe1_n(alu_op_n[7]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-EOR [7:0]" *)    sn74ahct541 re0 (.a(eor_out[7:0]), .oe1_n(alu_op_n[8]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-EOR [15:8]" *)   sn74ahct541 re1 (.a(eor_out[15:8]),.oe1_n(alu_op_n[8]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-COM [7:0]" *)    sn74ahct541 rc0 (.a(com_out[7:0]), .oe1_n(alu_op_n[9]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-COM [15:8]" *)   sn74ahct541 rc1 (.a(com_out[15:8]),.oe1_n(alu_op_n[9]), .oe2_n(1'b0), .y(z[15:8]));

    // ---- flags ---------------------------------------------------------------------
    assign flag_h = c4;             // half-carry: carry into bit 4

    // V = A_msb ^ B_msb ^ S_msb ^ carry_out (active width); also C ^ binv (borrow on sub).
    wire [3:0] vx, vy, vz;
    (* purpose = "V partials A^B" *)
    sn74ahct86 v0 (.a({2'b0, adderA[15], adderA[7]}), .b({2'b0, adderB[15], adderB[7]}), .y(vx));
    (* purpose = "V partials S^Cout" *)
    sn74ahct86 v1 (.a({2'b0, sum[15], sum[7]}), .b({2'b0, c16, c8}), .y(vy));
    (* purpose = "V combine ; C^binv" *)
    sn74ahct86 v2 (.a({vx[1], vx[0], c16, c8}), .b({vy[1], vy[0], binv, binv}), .y(vz));
    // lanes: vz[0]=c8^binv, vz[1]=c16^binv, vz[2]=vx0^vy0, vz[3]=vx1^vy1
    wire c8x = vz[0], c16x = vz[1], v8 = vz[2], v16 = vz[3];

    // Z = NOR of the result over the active width (OR-reduce tree, then invert). Each level
    // is a distinct package (no intra-package feedback).
    wire [3:0] zr0, zr1, zr2;
    (* purpose = "Z-reduce pairs [7:0]" *)
    sn74ahct32 zl (.a({z[6], z[4], z[2], z[0]}), .b({z[7], z[5], z[3], z[1]}), .y(zr0));
    (* purpose = "Z-reduce pairs [15:8]" *)
    sn74ahct32 zh (.a({z[14], z[12], z[10], z[8]}), .b({z[15], z[13], z[11], z[9]}), .y(zr1));
    (* purpose = "Z-reduce quads" *)
    sn74ahct32 zq (.a({zr1[2], zr1[0], zr0[2], zr0[0]}), .b({zr1[3], zr1[1], zr0[3], zr0[1]}), .y(zr2));
    // zr2[0]=|z[3:0] zr2[1]=|z[7:4] zr2[2]=|z[11:8] zr2[3]=|z[15:12]
    wire [3:0] zhalf;
    (* purpose = "Z-reduce halves" *)
    sn74ahct32 zf (.a({2'b0, zr2[2], zr2[0]}), .b({2'b0, zr2[3], zr2[1]}), .y(zhalf));
    wire orlo = zhalf[0];           // |z[7:0]
    wire orhi = zhalf[1];           // |z[15:8]
    wire [3:0] zall;
    (* purpose = "Z-reduce all" *)
    sn74ahct32 za (.a({3'b0, orlo}), .b({3'b0, orhi}), .y(zall));
    wire orall = zall[0];           // |z[15:0]
    wire [5:0] zinv;
    (* purpose = "Z8=~orlo, Z16=~orall" *)
    sn74ahct04 zn (.a({4'b0, orall, orlo}), .y(zinv));
    wire z8 = zinv[0], z16 = zinv[1];

    // width mux: pick the 8- or 16-bit flag set {C,V,Z,N}.
    wire [3:0] fl;
    (* purpose = "flag width mux" *)
    sn74ahct157 fmux (.a({c8x, v8, z8, z[7]}), .b({c16x, v16, z16, z[15]}), .sel(alu_width), .g_n(1'b0), .y(fl));
    assign flag_n = fl[0];
    assign flag_z = fl[1];
    assign flag_v = fl[2];
    assign flag_c = fl[3];
endmodule
`default_nettype wire
