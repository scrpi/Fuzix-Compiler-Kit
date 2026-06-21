// sn74ahct574 — octal D-type flip-flop with 3-state outputs (74AHCT574), cell model.
//
// Part of BLIP's 74-series cell library (R-SIM-1). Positive-edge clocked;
// active-low output enable (OE_n). Q goes high-Z when OE_n is high.
//
// Timing: (CLK *> Q) is the clock-to-output propagation; $setup/$hold document
// the D-to-CLK constraints. (Icarus does not *enforce* $setup/$hold — it has no
// timing-check tasks — so the worst-case gate reads margins from the waveform;
// toolchain.md §5.2. Verilator ignores all of this and runs zero-delay.)
//
// NOTE: PROVISIONAL placeholder delays, not yet sourced from the SN74AHCT574
// datasheet corners (docs/reference/datasheets/sn74ahct574.pdf) — toolchain.md §10.3.

`timescale 1ns / 1ps

module sn74ahct574 (
    output [7:0] Q,
    input  [7:0] D,
    input        CLK,
    input        OE_n
);
    reg [7:0] q_int;

    // Sim power-on / reset state (R-CPU-7): a real FF is X until reset, but the
    // machine comes up in a defined state (front-panel deposit / reset). Without
    // this the benchmark accumulator stays X and never toggles, making the timed
    // run unrepresentative.
    initial q_int = 8'h00;

    // clk->Q tpd via intra-assignment delay: Icarus honors `#`, Verilator ignores
    // it (zero-delay) — so the same cell serves both engines. A `specify` clk->Q
    // path drove Q to x under -gspecify here (a flop has no combinational CLK->Q
    // path, and the path interacts badly with the tristate output assign).
    // Standardizing sequential-cell timing (specify edge paths / SDF vs this) is an
    // open methodology question — toolchain.md §10.3 / §10.4.
    always @(posedge CLK)
        q_int <= #8 D;

    assign Q = OE_n ? 8'bz : q_int;
    // setup/hold (D->CLK) are a worst-case/STA concern, toolchain.md §5.2 —
    // not enforced in this functional model (Icarus has no timing-check tasks).
endmodule
