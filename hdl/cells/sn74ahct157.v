// sn74ahct157 — quad 2-line to 1-line data selector/multiplexer (74AHCT157), cell model.
// SN74AHCT157 (TI). Four 2:1 muxes sharing one SELECT and one strobe /G (active LOW).
// With /G low: Y = A when SELECT=0, Y = B when SELECT=1. With /G high: all Y forced LOW
// (not 3-state). Non-inverting. Datasheet: docs/reference/datasheets/sn74ahct157.pdf.
//
// Four of these form cpu's 13-bit control-store address mux: SELECT = loading picks the
// loader's counter (boot) vs the micro-PC (run); /G tied low.
//
// Read-path specify delays = SN74AHCT157, VCC 5 V, CL = 50 pF, MAX (datasheet p.4):
// A/B -> Y 9.8 ns, SELECT -> Y 12 ns, /G -> Y 12 ns. (D-47: every cell carries timing.)
`timescale 1ns/1ps
`default_nettype none
module sn74ahct157 (
    input  wire [3:0] a,        // "0" data inputs (selected when sel = 0)
    input  wire [3:0] b,        // "1" data inputs (selected when sel = 1)
    input  wire       sel,      // common SELECT (A/B)
    input  wire       g_n,      // strobe /G, active LOW (high forces Y = 0)
    output wire [3:0] y
);
    assign y = g_n ? 4'b0000 : (sel ? b : a);

    specify
        (a   => y) = 9.8;       // tpd A -> Y (bit-aligned)
        (b   => y) = 9.8;       // tpd B -> Y
        (sel *> y) = 12;        // tpd SELECT -> Y
        (g_n *> y) = 12;        // tpd /G -> Y
    endspecify
endmodule
`default_nettype wire
