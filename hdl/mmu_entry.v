// mmu_entry — the MMU page-table entry latch (the LEFT-side register of the MMU, used by
// LDMMU/STMMU). Structural netlist of real chips (R-SIM-1, R-SIM-5; microcode.md §3.2 MMU_PT_OP).
//
// LDMMU stages the entry on LEFT (`MMU_ENTRY <- D`) and commits it with MMU_PT_OP=WRITE_ENTRY;
// STMMU reads the addressed table entry back IN here (MMU_PT_OP=READ_ENTRY) and then drives it onto
// LEFT (LEFT_SRC=MMU_ENTRY) for `D <- MMU_ENTRY`. So this 16-bit latch captures from one of two
// sources — LEFT on a write, the table read-back (`entry_rd`) on a read — and re-drives LEFT.
//
// Structure (the BOM): 8x sn74ahct157 (two 2:1 mux layers — read-vs-hold, then write-vs-that),
// 2x sn74ahct574 (the latch), 2x sn74ahct541 (the LEFT driver).
`timescale 1ns/1ps
`default_nettype none
module mmu_entry (
    input  wire        clk,
    input  wire [15:0] left_in,    // capture source on a WRITE (the value staged on LEFT, e.g. D)
    input  wire [10:0] entry_rd,   // capture source on a READ (the addressed table entry)
    input  wire        load_n,     // MMU_PT_OP == WRITE_ENTRY (active LOW) -> capture LEFT
    input  wire        read_n,     // MMU_PT_OP == READ_ENTRY  (active LOW) -> capture entry_rd
    input  wire        drive_n,    // LEFT_SRC == MMU_ENTRY     (active LOW) -> drive LEFT
    output wire [15:0] q,          // the entry value
    output wire [15:0] left_out    // q onto LEFT (3-state)
);
    wire [15:0] erd = {5'b00000, entry_rd};   // table read-back, zero-padded to 16

    // layer A: READ (read_n=0) picks entry_rd; else hold q.
    wire [15:0] sa;
    (* purpose = "MMU_ENTRY read/hold [3:0]" *)
    sn74ahct157 a0 (.a(erd[3:0]),   .b(q[3:0]),   .sel(read_n), .g_n(1'b0), .y(sa[3:0]));
    (* purpose = "MMU_ENTRY read/hold [7:4]" *)
    sn74ahct157 a1 (.a(erd[7:4]),   .b(q[7:4]),   .sel(read_n), .g_n(1'b0), .y(sa[7:4]));
    (* purpose = "MMU_ENTRY read/hold [11:8]" *)
    sn74ahct157 a2 (.a(erd[11:8]),  .b(q[11:8]),  .sel(read_n), .g_n(1'b0), .y(sa[11:8]));
    (* purpose = "MMU_ENTRY read/hold [15:12]" *)
    sn74ahct157 a3 (.a(erd[15:12]), .b(q[15:12]), .sel(read_n), .g_n(1'b0), .y(sa[15:12]));

    // layer B: WRITE (load_n=0) picks LEFT; else the read/hold result.
    wire [15:0] d;
    (* purpose = "MMU_ENTRY write/keep [3:0]" *)
    sn74ahct157 b0 (.a(left_in[3:0]),   .b(sa[3:0]),   .sel(load_n), .g_n(1'b0), .y(d[3:0]));
    (* purpose = "MMU_ENTRY write/keep [7:4]" *)
    sn74ahct157 b1 (.a(left_in[7:4]),   .b(sa[7:4]),   .sel(load_n), .g_n(1'b0), .y(d[7:4]));
    (* purpose = "MMU_ENTRY write/keep [11:8]" *)
    sn74ahct157 b2 (.a(left_in[11:8]),  .b(sa[11:8]),  .sel(load_n), .g_n(1'b0), .y(d[11:8]));
    (* purpose = "MMU_ENTRY write/keep [15:12]" *)
    sn74ahct157 b3 (.a(left_in[15:12]), .b(sa[15:12]), .sel(load_n), .g_n(1'b0), .y(d[15:12]));

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
