// sn74ahct541 — octal buffer / line driver with 3-state outputs (74AHCT541), cell model.
// SN74AHCT541 (TI). Eight non-inverting buffers; the outputs drive when BOTH enables
// /OE1 and /OE2 are LOW, else High-Z. Datasheet: docs/reference/datasheets/sn74ahct541.pdf.
//
// In cpu, one per control-store SRAM: drives the EEPROM byte onto that SRAM's I/O during
// the boot copy (enable = run, i.e. ~loading), and tri-states during run so each SRAM
// drives its own slice of the control word. This is the per-chip isolation that lets a
// single shared boot-write source feed 13 SRAMs that read out in parallel.
//
// Specify delays = SN74AHCT541, VCC 5 V, CL = 50 pF, MAX (datasheet switching char.):
// A -> Y 9.5 ns; /OE -> Y enable/disable 12 ns. (D-47: every cell carries timing.)
`timescale 1ns/1ps
`default_nettype none
module sn74ahct541 (
    input  wire [7:0] a,
    input  wire       oe1_n,    // /OE1, active LOW
    input  wire       oe2_n,    // /OE2, active LOW
    output wire [7:0] y
);
    assign y = (~oe1_n & ~oe2_n) ? a : 8'bz;

    specify
        (a     => y) = 9.5;             // tpd A -> Y (bit-aligned)
        (oe1_n *> y) = (12, 12, 12);    // /OE1 -> Y enable (tPZH/tPZL) / disable (tPHZ/tPLZ)
        (oe2_n *> y) = (12, 12, 12);    // /OE2 -> Y
    endspecify
endmodule
`default_nettype wire
