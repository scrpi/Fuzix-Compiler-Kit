// tb_icarus — Icarus testbench for the engine benchmark (TIMED run).
//
// Clocks add_accum for N cycles with the cell library's specify delays active
// (run iverilog with -gspecify). Measures throughput as wall-clock around `vvp`
// (see sim/bench/README.md): cycles / wall-second = the timed-sim rate.
//
// Period (20 ns) is chosen so the provisional 8 ns reg + 6 ns adder delays settle
// within a half-period; it is a throughput probe, not a timing-margin check
// (worst-case timing is a separate concern, toolchain.md §5.2).

`timescale 1ns / 1ps

module tb;
    parameter integer N = 2000000;   // clock cycles to run

    reg        clk  = 1'b0;
    reg        oe_n = 1'b0;
    reg  [7:0] din  = 8'h01;
    wire [7:0] acc;

    add_accum dut (.acc(acc), .din(din), .clk(clk), .oe_n(oe_n));

    integer i;
    initial begin
        for (i = 0; i < N; i = i + 1) begin
            #10 clk = 1'b1;
            #10 clk = 1'b0;
        end
        $display("ICARUS done: %0d cycles, final acc=%0d, sim_time=%0t", N, acc, $time);
        $finish;
    end
endmodule
