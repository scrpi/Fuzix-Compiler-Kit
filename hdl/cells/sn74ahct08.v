// sn74ahct08 — quadruple 2-input AND gate (74AHCT08), cell model.
// SN74AHCT08 (TI). Four independent 2-input AND gates, Y = A & B. Datasheet:
// docs/reference/datasheets/sn74ahct08.pdf.
//
// Used by the microsequencer to gate a conditional branch: the BRANCH load enable is
// branch_active & cond_taken, so the µPC loads NEXT_ADDR only when the selected condition
// (after polarity) is true (microcode.md §2).
//
// Specify delay = SN74AHCT08, VCC 5 V, CL = 50 pF, MAX (datasheet §6.6): A/B -> Y 9 ns.
// (D-47: every cell carries timing.)
`timescale 1ns/1ps
`default_nettype none
module sn74ahct08 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [3:0] y
);
    assign y = a & b;

    specify
        (a => y) = 9;           // tpd A -> Y (bit-aligned)
        (b => y) = 9;           // tpd B -> Y
    endspecify
endmodule
`default_nettype wire
