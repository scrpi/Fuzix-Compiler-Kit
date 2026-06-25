// left_lane — the LEFT-bus byte-lane steer: the operand-widening stage that sits in front of
// the ALU's LEFT input. Structural netlist of real chips (R-SIM-1, R-SIM-5; microcode.md §3.2
// LEFT_LANE; cpu-physical-construction.md §6.4(a)).
//
// Lane steering — zero-/sign-extend a byte to 16 bits, or move the high byte down onto the low
// lane — is a LEFT_LANE operation on the operand ENTERING the ALU, not a per-register output
// feature. So ONE source-agnostic block sits on LEFT and works on whatever drove it (a register
// or MDR). It maps the raw 16-bit LEFT bus (left_raw, the wired-OR of the source drivers) to the
// ALU's left input under the decoded LEFT_LANE:
//
//   FULL16        left = left_raw                            (a real 16-bit register operand)
//   LOW           left = {8'h00,            left_raw[7:0]}   (zero-extend the low byte)
//   SIGN_EXT      left = {{8{left_raw[7]}}, left_raw[7:0]}   (sign-extend the low byte)
//   HIGH_TO_LOW   left = {8'h00,            left_raw[15:8]}  (high byte down onto the low lane)
//
// Structure (the BOM): 6x sn74ahct157 (2:1 muxes, two 4-bit halves per 8-bit lane).
//   low lane  (lo0/lo1): HIGH_TO_LOW picks left_raw[15:8]; every other mode picks left_raw[7:0].
//   high lane: layer SX (sx0/sx1) picks the sign byte vs 0x00 (is it SIGN_EXT?); layer FULL
//              (hi0/hi1) picks left_raw[15:8] vs the SX layer (is it FULL16?). Net effect:
//              FULL16 -> raw high byte; SIGN_EXT -> sign byte; LOW / HIGH_TO_LOW -> 0x00.
//
// No-inverter mux idiom: a '157 selects A when SEL=0, so the active-LOW one-hot LEFT_LANE strobe
// drives SEL directly — the asserted line (LOW) picks the A input.
`timescale 1ns/1ps
`default_nettype none
module left_lane (
    input  wire [15:0] left_raw,     // the raw LEFT bus (whatever register/MDR drove it)
    input  wire [3:0]  left_lane_n,  // decoded LEFT_LANE one-hot, active LOW:
                                     //   [0]=FULL16 [1]=LOW [2]=SIGN_EXT [3]=HIGH_TO_LOW
    output wire [15:0] left          // steered operand -> ALU left input
);
    // The sign byte: the low-lane MSB fanned out to 8 bits (pure wiring). For SIGN_EXT the low
    // lane is left_raw[7:0], so the sign bit is left_raw[7].
    wire [7:0] sign_byte = {8{left_raw[7]}};

    // ---- low lane: HIGH_TO_LOW (SEL=0) -> raw high byte; else -> raw low byte ----
    (* purpose = "LEFT low lane: high->low? [3:0]" *)
    sn74ahct157 lo0 (.a(left_raw[11:8]),  .b(left_raw[3:0]), .sel(left_lane_n[3]), .g_n(1'b0), .y(left[3:0]));
    (* purpose = "LEFT low lane: high->low? [7:4]" *)
    sn74ahct157 lo1 (.a(left_raw[15:12]), .b(left_raw[7:4]), .sel(left_lane_n[3]), .g_n(1'b0), .y(left[7:4]));

    // ---- high lane, layer SX: SIGN_EXT (SEL=0) -> sign byte; else -> 0x00 --------
    wire [7:0] sx;
    (* purpose = "LEFT high lane SX: sign/0 [3:0]" *)
    sn74ahct157 sx0 (.a(sign_byte[3:0]), .b(4'h0), .sel(left_lane_n[2]), .g_n(1'b0), .y(sx[3:0]));
    (* purpose = "LEFT high lane SX: sign/0 [7:4]" *)
    sn74ahct157 sx1 (.a(sign_byte[7:4]), .b(4'h0), .sel(left_lane_n[2]), .g_n(1'b0), .y(sx[7:4]));

    // ---- high lane, layer FULL: FULL16 (SEL=0) -> raw high byte; else -> SX ------
    (* purpose = "LEFT high lane: raw/SX [3:0]" *)
    sn74ahct157 hi0 (.a(left_raw[11:8]),  .b(sx[3:0]), .sel(left_lane_n[0]), .g_n(1'b0), .y(left[11:8]));
    (* purpose = "LEFT high lane: raw/SX [7:4]" *)
    sn74ahct157 hi1 (.a(left_raw[15:12]), .b(sx[7:4]), .sel(left_lane_n[0]), .g_n(1'b0), .y(left[15:12]));
endmodule
`default_nettype wire
