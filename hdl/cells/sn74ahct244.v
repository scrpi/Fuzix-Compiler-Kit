// sn74ahct244 — octal buffer / line driver with 3-state outputs (74AHCT244), cell model.
// SN74AHCT244 (TI). Eight non-inverting buffers in TWO independent 4-bit groups, each with
// its own active-low output enable: 1OE# gates A[3:0] -> Y[3:0], 2OE# gates A[7:4] -> Y[7:4];
// a group's outputs are High-Z when its OE# is HIGH. (This is the difference from the '541,
// whose single enable pair gates all eight together.) Datasheet:
// docs/reference/datasheets/sn74ahct244.pdf.
//
// The register board (cpu-physical-construction.md §6.2) uses two of these as a 16-bit LEFT
// driver — one per byte, both group-enables tied to the single decoded drive-LEFT strobe.
//
// Specify delays = SN74AHCT244, VCC 5 V, CL = 50 pF, MAX (datasheet §5.6 switching char.):
// A -> Y 9.5 ns (tPLH/tPHL); OE# -> Y enable 13 ns (tPZH/tPZL) / disable 13 ns (tPHZ/tPLZ).
// (D-47: every cell carries timing.)
`timescale 1ns/1ps
`default_nettype none
module sn74ahct244 (
    input  wire [7:0] a,
    input  wire       oe1_n,    // 1OE#, active LOW — gates a[3:0] -> y[3:0]
    input  wire       oe2_n,    // 2OE#, active LOW — gates a[7:4] -> y[7:4]
    output wire [7:0] y
);
    assign y[3:0] = oe1_n ? 4'bz : a[3:0];
    assign y[7:4] = oe2_n ? 4'bz : a[7:4];

    specify
        (a     => y) = 9.5;             // tpd A -> Y (bit-aligned)
        (oe1_n *> y) = (13, 13, 13);    // 1OE# -> Y[3:0] enable (tPZH/tPZL) / disable (tPHZ/tPLZ)
        (oe2_n *> y) = (13, 13, 13);    // 2OE# -> Y[7:4]
    endspecify
endmodule
`default_nettype wire
