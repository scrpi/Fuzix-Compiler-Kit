// sn74act153 — dual 4-line to 1-line data selector/multiplexer (74ACT153), cell model.
// SN74ACT153 (TI). Two independent 4:1 muxes sharing the two select lines A (LSB) and
// B (MSB). Each channel: four data inputs C0..C3, an active-low output strobe G#, and
// output Y. When enabled (G# low), Y = C[{B,A}]; when disabled (G# high), Y = 0.
// Datasheet: docs/reference/datasheets/sn74act153.pdf.
//
// Six of these build the microsequencer's 12-bit next-address load mux: each '153 muxes
// two of the twelve bits among the four sources {NEXT_ADDR, opcode-LUT target, fetch
// entry, return}, selected by the two shared select lines the USEQ_OP decode drives.
//
// Specify delays = SN74ACT153, VCC 5 V, CL = 50 pF, -40..125°C, MAX (datasheet §5.6):
// select A/B -> Y 8.8 ns, data C -> Y 8.2 ns, strobe G -> Y 7.8 ns. (D-47.)
`timescale 1ns/1ps
`default_nettype none
module sn74act153 (
    input  wire       a,        // select bit 0 (LSB), shared by both channels
    input  wire       b,        // select bit 1 (MSB), shared
    input  wire       g1_n,     // channel 1 output strobe, active LOW
    input  wire [3:0] c1,       // channel 1 data inputs (c1[k] = C k)
    output wire       y1,       // channel 1 output
    input  wire       g2_n,     // channel 2 output strobe, active LOW
    input  wire [3:0] c2,       // channel 2 data inputs
    output wire       y2        // channel 2 output
);
    assign y1 = g1_n ? 1'b0 : c1[{b, a}];
    assign y2 = g2_n ? 1'b0 : c2[{b, a}];

    specify
        (a    *> y1) = 8.8;     // tpd select -> Y
        (b    *> y1) = 8.8;
        (c1   *> y1) = 8.2;     // tpd data -> Y
        (g1_n *> y1) = 7.8;     // tpd strobe -> Y
        (a    *> y2) = 8.8;
        (b    *> y2) = 8.8;
        (c2   *> y2) = 8.2;
        (g2_n *> y2) = 7.8;
    endspecify
endmodule
`default_nettype wire
