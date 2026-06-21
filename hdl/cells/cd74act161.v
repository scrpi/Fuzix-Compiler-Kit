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
// CLK->RCO 15.2 ns, ENT->RCO 9.8 ns, CLR#->Q/RCO 15 ns; fmax ~91 MHz. CLK->Q and
// CLR#->Q are modelled with an intra-assignment `#15` (Icarus honours it; Verilator
// ignores it) — the working mechanism, since a `specify` clk->Q path drives Q to x
// under Icarus -gspecify (see sn74ahct574). The combinational ENT->RCO is a
// `specify` path. Per the always-timed policy (D-47) every cell carries its timing;
// setup/hold (D->CLK) is not enforced — Icarus has no timing-check tasks
// (toolchain.md §5.2), and worst-case margin is a separate STA concern.
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
        if (!clr_n)         q <= #15 4'b0000;       // async clear, tpd CLR# -> Q
        else if (!load_n)   q <= #15 p;             // sync load,   tpd CLK  -> Q
        else if (enp & ent) q <= #15 q + 4'b0001;   // count up,    tpd CLK  -> Q
        // else hold
    end
    assign rco = ent & (&q);    // RCO = ENT AND (Q == 1111)

    specify
        (ent *> rco) = 9.8;     // tpd ENT -> RCO (combinational)
    endspecify
endmodule
`default_nettype wire
