// cd74act161 — 4-bit synchronous binary counter with async clear (74ACT161), cell model.
// CD74ACT161 (TI). Positive-edge clocked. Asynchronous master reset CLR# (active
// LOW) forces Q=0 regardless of the clock; synchronous parallel load LOAD# (active
// LOW) loads P on the clock edge; counts up when both enables ENP and ENT are HIGH
// (LOAD# HIGH), and holds otherwise. RCO (ripple carry out) is HIGH when ENT is
// HIGH and the count is at terminal value (1111) — used to cascade stages.
// Datasheet: docs/reference/datasheets/cd74act161.pdf.
//
// Five of these cascade (ripple carry: RCO -> next ENT, with ENP the shared
// enable) into uc_loader's 17-bit address counter. CLR# is the active-low boot
// reset; ENP/ENT carry the "not done" enable that stops the count at the last chip.
//
// Timing (datasheet p.8, CD74ACT161, -40..85C, CL=50pF, MAX): CLK->Q 15 ns,
// CLK->RCO 15.2 ns, ENT->RCO 9.8 ns, CLR#->Q/RCO 15 ns; fmax ~91 MHz. The
// sequential CLK->Q / CLR#->Q delays are NOT encoded: a `#` delay would corrupt
// the zero-delay functional loader run (which clocks faster than a real '161 to
// keep sim time short — the real boot clock is slow, ~100s of kHz), and a
// `specify` clk->Q path drives Q to x under Icarus -gspecify (see sn74ahct574).
// Sequential-cell timing is the open methodology question (toolchain.md
// §10.3/§10.4); this model is zero-delay and the numbers above are recorded for
// when that is settled.
`timescale 1ns/1ps
`default_nettype none
module cd74act161 (
    input  wire       clk,
    input  wire       clr_n,    // async master reset (active LOW)
    input  wire       load_n,   // sync parallel load (active LOW)
    input  wire       enp,      // count enable P
    input  wire       ent,      // count enable T
    input  wire [3:0] p,        // parallel load data
    output reg  [3:0] q,
    output wire       rco       // ripple carry out
);
    initial q = 4'b0000;        // defined power-on state (R-CPU-7; CLR# clears it at boot)
    always @(posedge clk or negedge clr_n) begin
        if (!clr_n)         q <= 4'b0000;       // asynchronous clear
        else if (!load_n)   q <= p;             // synchronous parallel load
        else if (enp & ent) q <= q + 4'b0001;   // count up
        // else hold
    end
    assign rco = ent & (&q);    // RCO = ENT AND (Q == 1111)
endmodule
`default_nettype wire
