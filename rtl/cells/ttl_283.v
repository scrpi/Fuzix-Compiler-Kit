// ttl_283 — 4-bit binary full adder (74x283), gate-level cell model.
//
// Part of BLIP's 74-series cell library (R-SIM-1). Combinational:
//   {C4, S} = A + B + C0
//
// Timing: the `specify` path delays make this a *timing-accurate* model when
// the simulator honors specify (Icarus: -gspecify). Verilator ignores them and
// runs the same logic zero-delay (the two-engine split, toolchain.md §4.2).
//
// NOTE: the delay numbers below are PROVISIONAL placeholders (representative of
// 74AHCT/ACT @5V), not yet sourced from a chosen vendor's datasheet corners —
// see toolchain.md §10.3 (cell-library timing data).

`timescale 1ns / 1ps

module ttl_283 (
    output [3:0] S,
    output       C4,
    input  [3:0] A,
    input  [3:0] B,
    input        C0
);
    assign {C4, S} = {1'b0, A} + {1'b0, B} + {4'b0, C0};

    specify
        (A  *> S)  = 6.0;
        (B  *> S)  = 6.0;
        (C0 *> S)  = 5.0;
        (A  *> C4) = 5.0;
        (B  *> C4) = 5.0;
        (C0 *> C4) = 4.0;
    endspecify
endmodule
