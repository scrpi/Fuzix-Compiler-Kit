// sn74f283 — 4-bit binary full adder with fast carry (74F283), cell model.
// SN74F283 (TI). Combinational: {C4, S} = A + B + C0. FAST bipolar TTL, used for
// its quick carry path: BLIP's 16-bit add cascades four of these (ripple carry),
// so the per-stage carry-in -> carry-out delay (C0 -> C4) sets the adder's critical
// path. Datasheet: docs/reference/datasheets/sn74f283.pdf.
//
// (74F is a deliberate departure from the 74AHCT/74ACT family of D-37 / R-HW-2 —
// bipolar, higher power, but level-compatible (TTL output / TTL-threshold input) —
// taken for the faster carry.)
//
// Part of BLIP's 74-series cell library (R-SIM-1). The `specify` path delays make
// this a timing-accurate model under -gspecify; Verilator ignores them and runs
// the same logic zero-delay (the two-engine split, toolchain.md §4.2).
//
// Timing: SN74F283, VCC = 4.5-5.5 V, 0..70C, CL = 50 pF, RL = 500 ohm, MAX
// (datasheet switching characteristics): An/Bn or C0 -> Sn = 14 ns, -> C4 = 10.5 ns.
// (At VCC 5 V / 25C the maxes are 9.5 ns to Sn and 7.5 ns to C4.)
`timescale 1ns / 1ps

module sn74f283 (
    output [3:0] S,
    output       C4,
    input  [3:0] A,
    input  [3:0] B,
    input        C0
);
    assign {C4, S} = {1'b0, A} + {1'b0, B} + {4'b0, C0};

    specify
        (A  *> S)  = 14;       // tpd An -> Sn
        (B  *> S)  = 14;       // tpd Bn -> Sn
        (C0 *> S)  = 14;       // tpd C0 -> Sn
        (A  *> C4) = 10.5;     // tpd An -> Cout
        (B  *> C4) = 10.5;     // tpd Bn -> Cout
        (C0 *> C4) = 10.5;     // tpd C0 -> Cout (the ripple-carry critical path)
    endspecify
endmodule
