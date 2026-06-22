// sn74ahct139 — dual 2-line to 4-line decoder/demultiplexer (74AHCT139), cell model.
// SN74AHCT139 (TI). Two independent decoders in one package. Each has an active-low
// enable G#; when enabled (G# low) the output selected by {B, A} (B the MSB) goes LOW
// and the other three stay HIGH; when disabled (G# high) all four outputs are HIGH.
// Datasheet: docs/reference/datasheets/sn74ahct139.pdf.
//
// Used by the control-word decoder: a 2-bit binary control field drives one half's
// {B, A}, and the four active-low outputs are that field's one-hot strobe lines. The
// '139 is the natural part for the many 2-bit datapath fields (a '138 is 3->8, a '154
// is unobtainable), one package decoding two fields.
//
// Read-path `specify` delays = SN74AHCT139, VCC 5 V, CL = 50 pF, MAX (datasheet p.4):
// select A/B -> Y 10.5 ns, enable G -> Y 9.5 ns. Honored by the timed Icarus engine
// (-gspecify); ignored zero-delay.
`timescale 1ns/1ps
`default_nettype none
module sn74ahct139 (
    input  wire       g1_n,     // decoder 1 enable, active LOW
    input  wire       a1,       // decoder 1 select bit 0 (LSB)
    input  wire       b1,       // decoder 1 select bit 1 (MSB)
    output wire [3:0] y1,       // decoder 1 outputs, active LOW
    input  wire       g2_n,     // decoder 2 enable, active LOW
    input  wire       a2,       // decoder 2 select bit 0 (LSB)
    input  wire       b2,       // decoder 2 select bit 1 (MSB)
    output wire [3:0] y2        // decoder 2 outputs, active LOW
);
    assign y1 = ~g1_n ? ~(4'd1 << {b1, a1}) : 4'hf;
    assign y2 = ~g2_n ? ~(4'd1 << {b2, a2}) : 4'hf;

    specify
        (a1   *> y1) = 10.5;    // tpd select -> Y  (CL=50pF, max)
        (b1   *> y1) = 10.5;
        (g1_n *> y1) = 9.5;     // tpd enable -> Y
        (a2   *> y2) = 10.5;
        (b2   *> y2) = 10.5;
        (g2_n *> y2) = 9.5;
    endspecify
endmodule
`default_nettype wire
