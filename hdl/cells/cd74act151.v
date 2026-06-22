// cd74act151 — 8-line to 1-line data selector/multiplexer (74ACT151), cell model.
// CD74ACT151 (TI). One 8:1 mux: data inputs D0..D7, three select lines A (LSB), B,
// C (MSB), an active-low output strobe G#, and complementary outputs Y and W (= ~Y).
// When enabled (G# low), Y = D[{C,B,A}]; when disabled (G# high), Y = 0 (W = 1).
// Datasheet: docs/reference/datasheets/cd74act151.pdf.
//
// Two of these (plus a 2:1 merge) build the microsequencer's 16:1 condition mux: each
// '151 selects one of eight microconditions by UCOND_SEL[2:0], and UCOND_SEL[3] picks the
// low or high group (microcode.md §2).
//
// Specify delays = CD74ACT151, VCC 5 V, CL = 50 pF, -40..85°C, MAX (datasheet §4.6):
// select A/B/C -> Y 18.4 ns, data D -> Y 14.1 ns, strobe G -> Y 11 ns (-> W: 19.6 / 15.4
// / 11). The select path is this part's slow path — relevant to the R-CLK-1 margin. (D-47.)
`timescale 1ns/1ps
`default_nettype none
module cd74act151 (
    input  wire       a,        // select bit 0 (LSB)
    input  wire       b,        // select bit 1
    input  wire       c,        // select bit 2 (MSB)
    input  wire       g_n,      // output strobe, active LOW
    input  wire [7:0] d,        // data inputs (d[k] = D k)
    output wire       y,        // output
    output wire       w         // complementary output (= ~Y)
);
    assign y = g_n ? 1'b0 : d[{c, b, a}];
    assign w = ~y;

    specify
        (a   *> y) = 18.4;      // tpd select -> Y
        (b   *> y) = 18.4;
        (c   *> y) = 18.4;
        (d   *> y) = 14.1;      // tpd data -> Y
        (g_n *> y) = 11;        // tpd strobe -> Y
        (a   *> w) = 19.6;      // tpd select -> W
        (b   *> w) = 19.6;
        (c   *> w) = 19.6;
        (d   *> w) = 15.4;      // tpd data -> W
        (g_n *> w) = 11;        // tpd strobe -> W
    endspecify
endmodule
`default_nettype wire
