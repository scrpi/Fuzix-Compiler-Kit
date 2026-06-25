// alu_arithmetic — the arithmetic section of the ALU: the 16-bit adder and the ADD/ADC/SUB/
// SBC/NEG ops, with the arithmetic flags (V, borrow-convention C, half-carry H). Structural
// netlist of real chips (R-SIM-1, R-SIM-5; hardware.md §2, §9.2 "discrete adders").
//
// Subtraction is two's-complement add: RIGHT is XOR-inverted (binv) for SUB/SBC/NEG and the
// carry-in supplies the +1. NEG forces A=0, B=~LEFT, cin=1. Carry follows the BORROW
// convention on subtracts (C = carry_out XOR binv): C=1 means borrow (LEFT < RIGHT unsigned).
// Overflow V = A_msb ^ B_msb ^ S_msb ^ carry_out on the post-inversion adder inputs; H =
// carry into bit4. Width: W8 takes V/C from the bit-7 boundary, W16 from bit15.
//
// The sum drives the shared ALU result bus `z` through tri-state buffers whenever any
// arithmetic op is selected (one driver of the wired-OR result mux, hardware.md §2). The
// computed flags are the arithmetic values; FLAG_WE/V_SRC/C_SRC on the CC board gate what
// actually lands in CC.
//
// Every chained gate crosses package boundaries: a single cell's `assign y = a OP b` is one
// atomic vector op, so a package output must never feed that same package's input.
`timescale 1ns/1ps
`default_nettype none
module alu_arithmetic (
    input  wire [15:0] left,
    input  wire [15:0] right,
    input  wire [15:0] alu_op_n,    // decoded ALU_OP one-hot, active LOW (uses [2,3,4,5,10])
    input  wire        alu_cin,     // ALU_CIN literal: 0=ZERO, 1=CC_C
    input  wire        alu_width,   // ALU_WIDTH: 0=W8, 1=W16
    input  wire        cc_c,        // current CC.C (carry-in for ADC/SBC and ALU_CIN=CC_C)
    output wire [15:0] z,           // tri-state: drives the result bus when an arith op runs
    output wire        flag_c_arith,// width-selected carry/borrow
    output wire        flag_v_arith,// width-selected overflow
    output wire        flag_h       // half-carry: carry into bit 4
);
    // ---- op strobes -> active-high senses ------------------------------------------
    wire [5:0] op;                  // [0]=ADD [1]=ADC [2]=SUB [3]=SBC [4]=NEG
    (* purpose = "arith op senses" *)
    sn74ahct04 ops (.a({1'b0, alu_op_n[10], alu_op_n[5], alu_op_n[4], alu_op_n[3], alu_op_n[2]}), .y(op));
    wire op_add = op[0], op_adc = op[1], op_sub = op[2], op_sbc = op[3], op_neg = op[4];

    // ---- control glue (levels in distinct packages; see header) --------------------
    //   L1: ga=SUB|SBC  force1=SUB|NEG  gb=ADC|SBC    p_addcin=ADD&ALU_CIN
    //   L2: binv=ga|NEG  usec=gb|p_addcin  or_ab=ADD|gb
    //   L3: cin=force1|p_usec_c  arith_active=or_ab|force1      p_usec_c=usec&CC.C
    wire [3:0] or1;
    (* purpose = "L1 OR: ga/force1/gb" *)
    sn74ahct32 orp1 (.a({1'b0, op_adc, op_sub, op_sub}), .b({1'b0, op_sbc, op_neg, op_sbc}), .y(or1));
    wire ga = or1[0], force1 = or1[1], gb = or1[2];

    wire [3:0] a1;
    (* purpose = "L1 AND: ADD and ALU_CIN" *)
    sn74ahct08 andp1 (.a({3'b0, op_add}), .b({3'b0, alu_cin}), .y(a1));
    wire p_addcin = a1[0];

    wire [3:0] or2;
    (* purpose = "L2 OR: binv/usec/or_ab" *)
    sn74ahct32 orp2 (.a({1'b0, op_add, gb, ga}), .b({1'b0, gb, p_addcin, op_neg}), .y(or2));
    wire binv = or2[0], usec = or2[1], or_ab = or2[2];

    wire [3:0] a2;
    (* purpose = "L2 AND: usec and CC.C" *)
    sn74ahct08 andp2 (.a({3'b0, usec}), .b({3'b0, cc_c}), .y(a2));
    wire p_usec_c = a2[0];

    wire [3:0] or3;
    (* purpose = "L3 OR: cin ; arith_active" *)
    sn74ahct32 orp3 (.a({2'b0, or_ab, force1}), .b({2'b0, force1, p_usec_c}), .y(or3));
    wire cin = or3[0], arith_active = or3[1];
    wire [5:0] invE;
    (* purpose = "arith_en_n = ~arith_active" *)
    sn74ahct04 ie (.a({5'b0, arith_active}), .y(invE));
    wire arith_en_n = invE[0];

    // ---- adder operand conditioning ------------------------------------------------
    // A = NEG ? 0 : LEFT (alu_op_n[10] = ~op_neg, so AND-mask). B = (NEG ? LEFT : RIGHT) ^ binv.
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

    // ---- sum -> result bus (tri-state when any arithmetic op is active) ------------
    (* purpose = "Z<-SUM [7:0]" *)  sn74ahct541 rs0 (.a(sum[7:0]),  .oe1_n(arith_en_n), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-SUM [15:8]" *) sn74ahct541 rs1 (.a(sum[15:8]), .oe1_n(arith_en_n), .oe2_n(1'b0), .y(z[15:8]));

    // ---- flags ---------------------------------------------------------------------
    assign flag_h = c4;             // half-carry: carry into bit 4
    // V = A_msb ^ B_msb ^ S_msb ^ carry_out (per width); also C ^ binv (borrow on sub).
    wire [3:0] vx, vy, vz;
    (* purpose = "V partials A^B" *)
    sn74ahct86 v0 (.a({2'b0, adderA[15], adderA[7]}), .b({2'b0, adderB[15], adderB[7]}), .y(vx));
    (* purpose = "V partials S^Cout" *)
    sn74ahct86 v1 (.a({2'b0, sum[15], sum[7]}), .b({2'b0, c16, c8}), .y(vy));
    (* purpose = "V combine ; C^binv" *)
    sn74ahct86 v2 (.a({vx[1], vx[0], c16, c8}), .b({vy[1], vy[0], binv, binv}), .y(vz));
    // lanes: vz[0]=c8^binv, vz[1]=c16^binv, vz[2]=v8, vz[3]=v16
    wire c8x = vz[0], c16x = vz[1], v8 = vz[2], v16 = vz[3];

    wire [3:0] cv;
    (* purpose = "arith C/V width mux" *)
    sn74ahct157 cvmux (.a({2'b0, v8, c8x}), .b({2'b0, v16, c16x}), .sel(alu_width), .g_n(1'b0), .y(cv));
    assign flag_c_arith = cv[0];
    assign flag_v_arith = cv[1];
endmodule
`default_nettype wire
