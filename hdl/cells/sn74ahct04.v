// sn74ahct04 — hex inverter (74AHCT04), cell model.
// SN74AHCT04 (TI). Six independent inverters, Y = ~A. Datasheet:
// docs/reference/datasheets/sn74ahct04.pdf.
//
// Used in cpu for run = ~loading (release the micro-PC when the boot copy ends).
//
// Read-path specify delay = SN74AHCT04, VCC 5 V, CL = 50 pF, MAX (datasheet §5.6):
// A -> Y 8.5 ns. (D-47: every cell carries timing.)
`timescale 1ns/1ps
`default_nettype none
module sn74ahct04 (
    input  wire [5:0] a,
    output wire [5:0] y
);
    assign y = ~a;

    specify
        (a => y) = 8.5;         // tpd A -> Y (bit-aligned)
    endspecify
endmodule
`default_nettype wire
