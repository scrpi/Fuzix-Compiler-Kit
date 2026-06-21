// sn74ahct138 — 3-line to 8-line decoder/demultiplexer (74AHCT138), cell model.
// SN74AHCT138 (TI). One enable is active-high (G1), two active-low (G2A#, G2B#);
// the addressed output (C B A, with C the MSB) goes LOW and all others HIGH, but
// only when enabled (G1 high, G2A# low, G2B# low) — otherwise all outputs are HIGH.
// Datasheet: docs/reference/datasheets/sn74ahct138.pdf.
//
// Two of these build uc_loader's 4->16 segment decoder (no '154 needed): the low
// three segment bits drive A,B,C of both, and the 4th bit picks which '138 is
// active via the complementary enable polarities (G1 high-true on one, G2A# /
// G2B# low-true on the other) — so no inverter is required.
//
// Read-path `specify` delays = SN74AHCT138, VCC 5 V, CL = 50 pF, MAX (datasheet
// p.4). Honored by the timed Icarus engine (-gspecify); ignored zero-delay.
`timescale 1ns/1ps
`default_nettype none
module sn74ahct138 (
    input  wire       a,        // select bit 0 (LSB)
    input  wire       b,        // select bit 1
    input  wire       c,        // select bit 2 (MSB)
    input  wire       g1,       // enable, active HIGH
    input  wire       g2a_n,    // enable, active LOW
    input  wire       g2b_n,    // enable, active LOW
    output wire [7:0] y         // decoded outputs, active LOW
);
    wire       enabled = g1 & ~g2a_n & ~g2b_n;
    wire [2:0] sel     = {c, b, a};
    assign y = enabled ? ~(8'd1 << sel) : 8'hff;

    specify
        (a     *> y) = 13;      // tpd select -> Y  (CL=50pF, max)
        (b     *> y) = 13;
        (c     *> y) = 13;
        (g1    *> y) = 11.5;    // tpd G1   -> Y
        (g2a_n *> y) = 12;      // tpd G2A# -> Y
        (g2b_n *> y) = 12;      // tpd G2B# -> Y
    endspecify
endmodule
`default_nettype wire
