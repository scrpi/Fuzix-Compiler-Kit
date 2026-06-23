// sn74ahct86 — quadruple 2-input exclusive-OR gate (74AHCT86), cell model.
// SN74AHCT86 (TI). Four independent 2-input XOR gates, Y = A ^ B. Datasheet:
// docs/reference/datasheets/sn74ahct86.pdf.
//
// Used by the microsequencer for condition polarity: cond_taken = cond ^ UCOND_POL, so
// both senses of every microcondition are reachable from one condition mux (microcode.md
// §2). The spare gates are available for the CC-derived terms (e.g. N⊻V) when the flags
// block lands.
//
// Specify delay = SN74AHCT86, VCC 5 V, CL = 50 pF, -40..85°C, MAX (datasheet §7.6):
// A/B -> Y 9 ns. (D-47: every cell carries timing.)
`timescale 1ns/1ps
`default_nettype none
module sn74ahct86 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [3:0] y
);
    assign y = a ^ b;

    specify
        (a => y) = 9;           // tpd A -> Y (bit-aligned)
        (b => y) = 9;           // tpd B -> Y
    endspecify
endmodule
`default_nettype wire
