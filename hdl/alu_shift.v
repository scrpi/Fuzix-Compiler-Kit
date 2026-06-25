// alu_shift — the shift section of the ALU: ASL / LSR / ASR / ROL / ROR on LEFT, qualified by
// ALU_SHIFT. Structural netlist of real chips (R-SIM-1, R-SIM-5; isa.md §8.5, §8.8).
//
// A shift is mostly wiring (a +1/-1 bit reindex) plus the bit shifted in and the bit shifted
// out (the carry). Left shifts (ASL/ROL): result = {LEFT[14:0], fill_lsb}, carry = LEFT[msb].
// Right shifts (LSR/ASR/ROR): result = {fill_msb, LEFT[15:1]}, carry = LEFT[0]. The fills:
// ASL/LSR shift in 0; ROL/ROR shift in CC.C; ASR replicates the sign (LEFT[msb]). Width only
// changes the msb position (bit15 for W16, bit7 for W8) — so the right-shift bit-7 input and
// the left-shift carry source are the only width-dependent points.
//
// The result drives the shared ALU result bus `z` (tri-state, gated by ALU_OP=SHIFT). The
// shift carry and V (= result-sign XOR carry) are exported for the top's flag mux to select
// over the arithmetic flags when SHIFT is the op. N/Z come from the result bus at the top.
`timescale 1ns/1ps
`default_nettype none
module alu_shift (
    input  wire [15:0] left,
    input  wire        cc_c,
    input  wire        alu_width,    // 0=W8 (bit7 msb), 1=W16 (bit15 msb)
    input  wire [7:0]  alu_shift_n,  // decoded ALU_SHIFT one-hot, active LOW
    input  wire        op_shift_n,   // = alu_op_n[11], active LOW (ALU_OP=SHIFT)
    output wire [15:0] z,            // tri-state shift result onto the bus
    output wire        shift_carry,  // bit shifted out
    output wire        shift_v,      // result-sign XOR carry
    output wire        op_shift      // active-high SHIFT select (for the top's flag mux)
);
    // ---- shift-type senses + the SHIFT op select -----------------------------------
    wire [5:0] shs;
    (* purpose = "shift senses + op_shift" *)
    sn74ahct04 shi (.a({op_shift_n, alu_shift_n[4], alu_shift_n[3], alu_shift_n[2], alu_shift_n[1], alu_shift_n[0]}), .y(shs));
    wire asl = shs[0], lsr = shs[1], asr = shs[2], rol = shs[3], ror_s = shs[4];
    assign op_shift = shs[5];

    // ---- fills (the shifted-in bits) -----------------------------------------------
    wire [3:0] shand;
    (* purpose = "fill_lsb; ASR&L15; ASR&L7; ROR&C" *)
    sn74ahct08 sha (.a({ror_s, asr, asr, rol}), .b({cc_c, left[7], left[15], cc_c}), .y(shand));
    wire fill_lsb = shand[0], asr_l15 = shand[1], asr_l7 = shand[2], ror_c = shand[3];

    wire [3:0] shor;
    (* purpose = "is_left; fill_msb16; fill_msb8" *)
    sn74ahct32 sho (.a({1'b0, asr_l7, asr_l15, asl}), .b({1'b0, ror_c, ror_c, rol}), .y(shor));
    wire is_left = shor[0], fill_msb16 = shor[1], fill_msb8 = shor[2];

    // ---- width muxes: left_msb (left-shift carry source); rs7 (right-shift bit-7 in) ----
    wire [3:0] wsh;
    (* purpose = "width mux: left_msb ; rs7" *)
    sn74ahct157 wmux (.a({2'b0, fill_msb8, left[7]}), .b({2'b0, left[8], left[15]}), .sel(alu_width), .g_n(1'b0), .y(wsh));
    wire left_msb = wsh[0], rs7 = wsh[1];

    // ---- the two shift candidates (pure wiring) and the left/right select ----------
    wire [15:0] left_shifted  = {left[14:0], fill_lsb};
    wire [15:0] right_shifted = {fill_msb16, left[15:9], rs7, left[7:1]};
    wire [15:0] sresult;
    (* purpose = "shift result mux [3:0]" *)   sn74ahct157 sr0 (.a(right_shifted[3:0]),   .b(left_shifted[3:0]),   .sel(is_left), .g_n(1'b0), .y(sresult[3:0]));
    (* purpose = "shift result [7:4]" *)   sn74ahct157 sr1 (.a(right_shifted[7:4]),   .b(left_shifted[7:4]),   .sel(is_left), .g_n(1'b0), .y(sresult[7:4]));
    (* purpose = "shift result [11:8]" *)  sn74ahct157 sr2 (.a(right_shifted[11:8]),  .b(left_shifted[11:8]),  .sel(is_left), .g_n(1'b0), .y(sresult[11:8]));
    (* purpose = "shift result [15:12]" *) sn74ahct157 sr3 (.a(right_shifted[15:12]), .b(left_shifted[15:12]), .sel(is_left), .g_n(1'b0), .y(sresult[15:12]));

    // ---- result onto the bus (tri-state when ALU_OP=SHIFT) -------------------------
    (* purpose = "Z<-SHIFT [7:0]" *)  sn74ahct541 rsh0 (.a(sresult[7:0]),  .oe1_n(op_shift_n), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-SHIFT [15:8]" *) sn74ahct541 rsh1 (.a(sresult[15:8]), .oe1_n(op_shift_n), .oe2_n(1'b0), .y(z[15:8]));

    // ---- shift flags: carry (out), N (result msb), V = N ^ carry --------------------
    wire [3:0] scm;
    (* purpose = "shift_carry = is_left ? left_msb : left[0]" *)
    sn74ahct157 scmux (.a({3'b0, left[0]}), .b({3'b0, left_msb}), .sel(is_left), .g_n(1'b0), .y(scm));
    assign shift_carry = scm[0];

    wire [3:0] nm;
    (* purpose = "n_shift = width ? res[15] : res[7]" *)
    sn74ahct157 nmux (.a({3'b0, sresult[7]}), .b({3'b0, sresult[15]}), .sel(alu_width), .g_n(1'b0), .y(nm));
    wire n_shift = nm[0];

    wire [3:0] sv;
    (* purpose = "shift_v = N ^ carry" *)
    sn74ahct86 svx (.a({3'b0, n_shift}), .b({3'b0, shift_carry}), .y(sv));
    assign shift_v = sv[0];
endmodule
`default_nettype wire
