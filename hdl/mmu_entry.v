// mmu_entry — the MMU page-table entry latch (the LEFT-side register of the MMU board, used by
// LDMMU/STMMU). Structural netlist of real chips (R-SIM-1, R-SIM-5; microcode.md §3.2 MMU_PT_OP).
//
// LDMMU stages the entry on LEFT (`MMU_ENTRY <- D`) and commits it with MMU_PT_OP=WRITE_ENTRY;
// STMMU reads it back onto LEFT (LEFT_SRC=MMU_ENTRY) for `D <- MMU_ENTRY`. This block is just
// that 16-bit holding latch and its LEFT driver — it captures LEFT on a write and re-drives LEFT
// on a read. The page-table register file and the translate logic (the rest of the MMU board,
// cpu-physical-construction.md §3.5) are a separate, not-yet-built subsystem; this latch lets the
// LDMMU/STMMU register transfer round-trip in the meantime.
//
// Structure (the BOM): 4x sn74ahct157 (recirculate mux: capture LEFT vs hold), 2x sn74ahct574
// (the 16-bit latch), 2x sn74ahct541 (the LEFT driver).
`timescale 1ns/1ps
`default_nettype none
module mmu_entry (
    input  wire        clk,
    input  wire [15:0] left_in,    // capture source (the value staged on LEFT, e.g. D)
    input  wire        load_n,     // MMU_PT_OP == WRITE_ENTRY (active LOW) -> capture LEFT
    input  wire        drive_n,    // LEFT_SRC == MMU_ENTRY (active LOW) -> drive LEFT
    output wire [15:0] q,          // the entry value
    output wire [15:0] left_out    // q onto LEFT (3-state)
);
    // recirculate mux: load_n asserted (LOW) picks A = LEFT (capture); else B = q (hold).
    wire [15:0] d;
    (* purpose = "MMU_ENTRY load/hold [3:0]" *)
    sn74ahct157 m0 (.a(left_in[3:0]),   .b(q[3:0]),   .sel(load_n), .g_n(1'b0), .y(d[3:0]));
    (* purpose = "MMU_ENTRY load/hold [7:4]" *)
    sn74ahct157 m1 (.a(left_in[7:4]),   .b(q[7:4]),   .sel(load_n), .g_n(1'b0), .y(d[7:4]));
    (* purpose = "MMU_ENTRY load/hold [11:8]" *)
    sn74ahct157 m2 (.a(left_in[11:8]),  .b(q[11:8]),  .sel(load_n), .g_n(1'b0), .y(d[11:8]));
    (* purpose = "MMU_ENTRY load/hold [15:12]" *)
    sn74ahct157 m3 (.a(left_in[15:12]), .b(q[15:12]), .sel(load_n), .g_n(1'b0), .y(d[15:12]));
    (* purpose = "MMU_ENTRY latch [7:0]" *)
    sn74ahct574 e0 (.Q(q[7:0]),  .D(d[7:0]),  .CLK(clk), .OE_n(1'b0));
    (* purpose = "MMU_ENTRY latch [15:8]" *)
    sn74ahct574 e1 (.Q(q[15:8]), .D(d[15:8]), .CLK(clk), .OE_n(1'b0));
    (* purpose = "MMU_ENTRY -> LEFT [7:0]" *)
    sn74ahct541 dl (.a(q[7:0]),  .oe1_n(drive_n), .oe2_n(1'b0), .y(left_out[7:0]));
    (* purpose = "MMU_ENTRY -> LEFT [15:8]" *)
    sn74ahct541 dh (.a(q[15:8]), .oe1_n(drive_n), .oe2_n(1'b0), .y(left_out[15:8]));
endmodule
`default_nettype wire
