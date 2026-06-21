// add_accum — 8-bit registered accumulator: acc <= acc + din, each clock.
//
// A deliberately REPRESENTATIVE benchmark slice (not part of the real BLIP CPU):
// a register feeding a combinational adder feeding back into the register, built
// structurally from the cell library — i.e. the "ALU + register + clocked path"
// the engine benchmark is meant to exercise (toolchain.md §10, §5.3).
//
//   two sn74f283 (carry-cascaded) form an 8-bit adder; one sn74ahct574 holds acc.
//
// The feedback path register -> adder -> register is the timed critical path the
// Icarus run measures, and the same netlist runs zero-delay under Verilator.

`timescale 1ns / 1ps

module add_accum (
    output [7:0] acc,
    input  [7:0] din,
    input        clk,
    input        oe_n
);
    wire [7:0] sum;
    wire       c_lo;            // carry out of the low nibble
    wire       c_hi;           // carry out of the high nibble (unused)

    sn74f283 add_lo (.S(sum[3:0]), .C4(c_lo), .A(acc[3:0]), .B(din[3:0]), .C0(1'b0));
    sn74f283 add_hi (.S(sum[7:4]), .C4(c_hi), .A(acc[7:4]), .B(din[7:4]), .C0(c_lo));
    sn74ahct574 reg8   (.Q(acc), .D(sum), .CLK(clk), .OE_n(oe_n));
endmodule
