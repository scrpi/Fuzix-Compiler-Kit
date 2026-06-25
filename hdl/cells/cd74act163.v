// cd74act163 — 4-bit synchronous binary counter with SYNCHRONOUS clear (74ACT163), cell model.
// CD74ACT163 (TI). Positive-edge clocked. Identical to the cd74act161 in this library
// EXCEPT the master clear CLR# (active LOW) is SYNCHRONOUS: it forces Q=0 on the next clock
// edge (not asynchronously). Synchronous parallel load LOAD# (active LOW) loads P on the
// edge; counts up when ENP and ENT are both HIGH (LOAD#/CLR# HIGH); holds otherwise. RCO
// (ripple carry out) is HIGH when ENT is HIGH and the count is at 1111 — cascades stages.
// Edge priority: CLR# > LOAD# > count > hold.
//
// The register board (cpu-physical-construction.md §6) builds every architectural register
// from four of these: the SYNCHRONOUS clear gives the deterministic, clock-aligned power-on
// state (R-CPU-7) that an async-clear '161 would not — which is why the registers use '163
// while the loader's free-running address counter uses '161 (async clear, uc_loader).
//
// Timing (datasheet docs/reference/datasheets/cd74act163.pdf, SCHS300B, switching char.
// CL = 50 pF, -40..85C, MAX): CLK->Q 15 ns, CLK->RCO 15.2 ns, ENT->RCO 9.8 ns; fmax 91 MHz —
// identical to this library's cd74act161 (same family; the sync vs async CLR# is the only
// logic difference). CLK->Q 15 ns via intra-assignment `#15` (Icarus honours it; Verilator
// ignores it) — the same mechanism as cd74act161/sn74ahct574 (a `specify` clk->Q path drives
// Q to x under -gspecify). The combinational ENT->RCO is a `specify` path. Every cell carries
// timing (D-47).
`timescale 1ns/1ps
`default_nettype none
module cd74act163 (
    input  wire       clk,
    input  wire       clr_n,    // SYNCHRONOUS master reset (active LOW) — clears on the clk edge
    input  wire       load_n,   // sync parallel load (active LOW)
    input  wire       enp,      // count enable P
    input  wire       ent,      // count enable T
    input  wire [3:0] p,        // parallel load data
    output reg  [3:0] q,
    output wire       rco       // ripple carry out
);
    initial q = 4'b0000;        // defined power-on state (R-CPU-7; CLR# also clears it synchronously)
    always @(posedge clk) begin
        if (!clr_n)         q <= #15 4'b0000;       // SYNC clear, tpd CLK -> Q
        else if (!load_n)   q <= #15 p;             // sync load,  tpd CLK -> Q
        else if (enp & ent) q <= #15 q + 4'b0001;   // count up,   tpd CLK -> Q
        // else hold
    end
    assign rco = ent & (&q);    // RCO = ENT AND (Q == 1111)

    specify
        (ent *> rco) = 9.8;     // tpd ENT -> RCO (combinational)
    endspecify
endmodule
`default_nettype wire
