// trap_encoder — the trap-vector priority encoder (microcode.md §2; interface.md §4.5). Structural
// netlist of real chips (R-SIM-1, R-SIM-5; R-CPU-6).
//
// On RETURN_FETCH (the instruction boundary — interface.md §4.5 samples interrupts only here), the
// sequencer normally returns the µPC to the fetch entry 0. This block INTERCEPTS that: if a trap is
// pending it redirects the µPC to that trap's fixed microroutine entry instead. Fixed priority
// NMI > IRQ (SWI/SWI2/SWI3 are ordinary opcodes reached by DISPATCH_IR, not here; illegal/priv land
// later as lower-priority sources). IRQ is already I-masked upstream (irq_masked = irq & ~CC.I), so
// a masked IRQ never reaches here.
//
// Structure (the BOM): 1x sn74ahct04 (~nmi), 1x sn74ahct08 (sel_irq, trap_pending), 1x sn74ahct32
// (any-source), 6x sn74ahct157 (the 12-bit entry-address priority mux over hardwired constants).
`timescale 1ns/1ps
`default_nettype none
module trap_encoder #(
    parameter [11:0] NMI_ENTRY = 12'd4,     // hardwired trap microroutine entries (reserved)
    parameter [11:0] IRQ_ENTRY = 12'd8
) (
    input  wire        nmi_pending,         // /NMI accepted (non-maskable)
    input  wire        irq_masked,          // /IRQ pending AND CC.I clear
    input  wire        retfetch_active,     // USEQ_OP == RETURN_FETCH (the instruction boundary)
    output wire [11:0] trap_entry,          // the selected trap entry (else don't-care)
    output wire        trap_pending         // 1 = redirect the fetch to trap_entry
);
    // ---- priority resolve: sel_irq = irq & ~nmi ; any = nmi | irq -----------------
    wire [5:0] niv;
    (* purpose = "~nmi_pending" *)
    sn74ahct04 nin (.a({5'b0, nmi_pending}), .y(niv));
    wire nmi_n = niv[0];
    wire [3:0] sand;
    (* purpose = "sel_irq; trap_pending" *)
    sn74ahct08 sa (.a({2'b0, retfetch_active, irq_masked}), .b({2'b0, any, nmi_n}), .y(sand));
    wire sel_irq      = sand[0];   // irq_masked & ~nmi_pending
    assign trap_pending = sand[1]; // retfetch_active & any
    wire [3:0] aor;
    (* purpose = "any = nmi | irq" *)
    sn74ahct32 ao (.a({3'b0, nmi_pending}), .b({3'b0, irq_masked}), .y(aor));
    wire any = aor[0];

    // ---- entry mux: layer IRQ (sel_irq ? IRQ_ENTRY : 0), then NMI (nmi ? NMI_ENTRY : that) ------
    wire [11:0] irq_lvl;
    (* purpose = "IRQ entry / 0 [3:0]" *)   sn74ahct157 i0 (.a(4'b0), .b(IRQ_ENTRY[3:0]),   .sel(sel_irq), .g_n(1'b0), .y(irq_lvl[3:0]));
    (* purpose = "IRQ entry / 0 [7:4]" *)   sn74ahct157 i1 (.a(4'b0), .b(IRQ_ENTRY[7:4]),   .sel(sel_irq), .g_n(1'b0), .y(irq_lvl[7:4]));
    (* purpose = "IRQ entry / 0 [11:8]" *)  sn74ahct157 i2 (.a(4'b0), .b(IRQ_ENTRY[11:8]),  .sel(sel_irq), .g_n(1'b0), .y(irq_lvl[11:8]));
    (* purpose = "NMI entry / IRQ-lvl [3:0]" *)  sn74ahct157 n0 (.a(irq_lvl[3:0]),   .b(NMI_ENTRY[3:0]),  .sel(nmi_pending), .g_n(1'b0), .y(trap_entry[3:0]));
    (* purpose = "NMI entry / IRQ-lvl [7:4]" *)  sn74ahct157 n1 (.a(irq_lvl[7:4]),   .b(NMI_ENTRY[7:4]),  .sel(nmi_pending), .g_n(1'b0), .y(trap_entry[7:4]));
    (* purpose = "NMI entry / IRQ-lvl [11:8]" *) sn74ahct157 n2 (.a(irq_lvl[11:8]),  .b(NMI_ENTRY[11:8]), .sel(nmi_pending), .g_n(1'b0), .y(trap_entry[11:8]));
endmodule
`default_nettype wire
