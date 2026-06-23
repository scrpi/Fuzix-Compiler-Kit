// sn74ahct32 — quadruple 2-input OR gate (74AHCT32), cell model.
// SN74AHCT32 (TI). Four independent 2-input OR gates, Y = A | B. Datasheet:
// docs/reference/datasheets/sn74ahct32.pdf.
//
// Inside each control-store block (microcode_store, opcode_lut) these form the per-chip
// /WE strobe: we_n[g] = cs_n[g] | clk (the loader's active-low select ORed with the clock
// phase), so /WE pulses LOW only for the selected chip while clk is LOW, latching the byte
// at the next edge. One more ORs the load terms into do_load in the microsequencer.
//
// Specify delay = SN74AHCT32, VCC 5 V, CL = 50 pF, MAX (datasheet §7.6): A/B -> Y 10 ns.
// (D-47: every cell carries timing.)
`timescale 1ns/1ps
`default_nettype none
module sn74ahct32 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [3:0] y
);
    assign y = a | b;

    specify
        (a => y) = 10;          // tpd A -> Y (bit-aligned)
        (b => y) = 10;          // tpd B -> Y
    endspecify
endmodule
`default_nettype wire
