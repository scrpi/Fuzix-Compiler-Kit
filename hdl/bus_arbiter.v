// bus_arbiter — the /BUSREQ ⇄ /BUSGRANT handshake (interface.md §4.6). Structural netlist of real
// chips (R-SIM-1, R-SIM-5; R-IF-4, R-DBG-2/-3).
//
// /BUSREQ is sampled at a bus-cycle boundary. When a request is pending and the CPU is neither
// booting nor holding a locked RMW (TAS_LOCK), the arbiter grants the bus: it asserts /BUSGRANT,
// tri-states A[23:0]//RD//WR (via bus_oe_n), and inhibits the CPU's own transfers (bus_inhibit) so
// an external master (DMA / the front panel) owns the bus. When /BUSREQ deasserts the grant drops
// and the CPU resumes. The grant is registered, so it changes only on a clock edge (a cycle
// boundary). A held grant stalls the CPU — the mechanism by which the panel halts the machine.
//
// Structure (the BOM): 2x sn74ahct04 (~/BUSREQ, ~loading, ~bus_locked, /BUSGRANT), 1x sn74ahct08
// (the grant AND-term), 1x sn74ahct574 (the registered grant).
`timescale 1ns/1ps
`default_nettype none
module bus_arbiter (
    input  wire clk,
    input  wire busreq_n,      // /BUSREQ (active LOW)
    input  wire bus_locked,    // TAS_LOCK asserted — do not relinquish the bus mid-RMW
    input  wire loading,       // boot copy — the CPU owns the bus
    output wire granted,       // 1 = bus granted away (tri-state + inhibit)
    output wire busgrant_n,    // /BUSGRANT (active LOW)
    output wire bus_oe_n       // 1 = float A//RD//WR (= granted)
);
    // grant_term = ~busreq_n & ~bus_locked & ~loading
    wire [5:0] iv;
    (* purpose = "~/BUSREQ; ~loading; ~bus_locked" *)
    sn74ahct04 in0 (.a({3'b0, bus_locked, loading, busreq_n}), .y(iv));
    wire req = iv[0], nload = iv[1], nlock = iv[2];
    wire [3:0] an;
    (* purpose = "grant = req & ~lock & ~loading" *)
    sn74ahct08 ga (.a({2'b0, an[0], req}), .b({2'b0, nload, nlock}), .y(an));
    // an[0] = req & nlock ; an[1] = an[0] & nload = grant_term  (feed-forward within the package)
    wire grant_term = an[1];

    // registered grant (changes only on a clock edge = a cycle boundary)
    wire [7:0] gq;
    (* purpose = "registered grant" *)
    sn74ahct574 greg (.Q(gq), .D({7'b0, grant_term}), .CLK(clk), .OE_n(1'b0));
    assign granted  = gq[0];
    assign bus_oe_n = gq[0];
    wire [5:0] gv;
    (* purpose = "/BUSGRANT = ~granted" *)
    sn74ahct04 in1 (.a({5'b0, gq[0]}), .y(gv));
    assign busgrant_n = gv[0];
endmodule
`default_nettype wire
