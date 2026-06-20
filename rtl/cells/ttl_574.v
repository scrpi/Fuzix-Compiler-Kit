// ttl_574 — octal D-type flip-flop with 3-state outputs (74x574), cell model.
//
// Part of BLIP's 74-series cell library (R-SIM-1). Positive-edge clocked;
// active-low output enable (OE_n). Q goes high-Z when OE_n is high.
//
// Timing: (CLK *> Q) is the clock-to-output propagation; $setup/$hold document
// the D-to-CLK constraints. (Icarus does not *enforce* $setup/$hold — it has no
// timing-check tasks — so the worst-case gate reads margins from the waveform;
// toolchain.md §5.2. Verilator ignores all of this and runs zero-delay.)
//
// NOTE: PROVISIONAL placeholder delays (representative 74AHCT/ACT @5V), not yet
// sourced from datasheet corners — toolchain.md §10.3.

`timescale 1ns / 1ps

module ttl_574 (
    output [7:0] Q,
    input  [7:0] D,
    input        CLK,
    input        OE_n
);
    reg [7:0] q_int;

    always @(posedge CLK)
        q_int <= D;

    assign Q = OE_n ? 8'bz : q_int;

    specify
        (CLK *> Q) = 8.0;                 // tpd clk -> Q (typ)
        $setup(D, posedge CLK, 5.0);      // documented; not enforced by Icarus
        $hold(posedge CLK, D, 0.0);
    endspecify
endmodule
