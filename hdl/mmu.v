// mmu — the memory management unit: translate a 16-bit logical address to the 24-bit physical
// address A[23:0], and reprogram the page table via LDMMU/STMMU. Structural netlist of real chips
// (R-SIM-1, R-SIM-5; hardware.md §3; interface.md §3.1; R-MEM-1/-5/-7; D-11/D-15).
//
// Geometry (hardware.md §3 / D-11): 8 KB pages. addr[12:0] (offset) -> A[12:0] straight through;
// addr[15:13] (slot, 1 of 8) indexes the page table; the slot's 11-bit physical page number drives
// A[23:13]. Physical = {PPN[10:0], offset[12:0]} = 16 MB / 2048 frames.
//
// Page table = a privileged register file: TWO maps (kernel + user) x 8 slots = 16 x 11-bit, here
// one is61c64 (AW=4, addressed by index = {map_bit, slot}). The ACTIVE map follows MMU_MAP_SEL:
// FOLLOW_M -> CC.M (supervisor=kernel), FORCE_KERNEL/USER -> constant. Map polarity: map_bit=1 is
// the kernel set (index 8..15), map_bit=0 user (0..7); FOLLOW_M = CC.M so supervisor uses kernel
// (cross-checked against the IRQ-entry FORCE_KERNEL). FROM_IMM8 (cross-map copy) is DEFERRED — it
// needs the not-yet-written copyin/copyout microcode — and falls back to FOLLOW_M.
//
// Reset = identity map (D-15, R-MEM-7, "no translation-off state" isa.md §6): during the boot copy
// (loading=1) the table is swept with identity entries (slot k -> PPN k, so A = {8'h00, addr}),
// piggybacking on the loader's address counter — so after boot, and after every reset, the table
// IS the identity map until LDMMU overwrites an entry. DIRECT_PHYSICAL (MMU_ADDR_SRC) bypasses the
// table with the identity PPN for vector/reset fetches regardless of the programmed entry.
//
// LDMMU stages the 11-bit entry on LEFT into MMU_ENTRY, then WRITE_ENTRY commits it to the indexed
// slot; STMMU's READ_ENTRY drives the indexed entry out (`entry_rd`) for MMU_ENTRY to capture.
//
// Structure (the BOM): 1x is61c64 (the 16x11 table), 2x sn74ahct541 (table write buffer), 6x
// sn74ahct157 (boot/run addr mux, write-data mux, DIRECT_PHYSICAL mux), 1x sn74ahct04, 1x
// sn74ahct08, 2x sn74ahct32 (map-bit, write-active, /WE strobe). A[23:0] is south-edge wiring.
`timescale 1ns/1ps
`default_nettype none
module mmu (
    input  wire        clk,
    input  wire        loading,        // boot: identity-load the table off the loader counter
    input  wire [11:0] loader_addr,    // boot sweep address (low 4 bits index the table)
    input  wire [15:0] addr_logical,   // the logical address to translate (PC/MAR, muxed upstream)
    input  wire [3:0]  mmu_addr_n,     // MMU_ADDR_SRC one-hot ([2]=DIRECT_PHYSICAL)
    input  wire [3:0]  mmu_map_n,      // MMU_MAP_SEL one-hot ([0]=FOLLOW_M [1]=FORCE_KERNEL [2]=FORCE_USER)
    input  wire [3:0]  mmu_pt_n,       // MMU_PT_OP one-hot ([1]=WRITE_ENTRY [2]=READ_ENTRY)
    input  wire        cc_m,           // CC.M (supervisor) — FOLLOW_M map source
    input  wire [10:0] entry_in,       // PPN to write on WRITE_ENTRY (from MMU_ENTRY)
    output wire [10:0] entry_rd,       // addressed PPN read-back (STMMU -> MMU_ENTRY)
    output wire [23:0] a               // the physical address
);
    // ---- map_bit + write-active ------------------------------------------------
    wire [5:0] iv;
    (* purpose = "~FORCE_KERNEL; ~WRITE_ENTRY" *)
    sn74ahct04 in0 (.a({4'b0000, mmu_pt_n[1], mmu_map_n[1]}), .y(iv));
    wire force_kernel = iv[0];          // ~mmu_map_n[1]
    wire run_write    = iv[1];          // ~mmu_pt_n[1] (WRITE_ENTRY)
    wire [3:0] follow;
    (* purpose = "follow = CC.M & ~FORCE_USER" *)
    sn74ahct08 an0 (.a({3'b0, cc_m}), .b({3'b0, mmu_map_n[2]}), .y(follow));
    wire [3:0] mor;
    (* purpose = "write_active = loading|WRITE; map_bit = kernel|follow" *)
    sn74ahct32 or0 (.a({2'b0, force_kernel, loading}), .b({2'b0, follow[0], run_write}), .y(mor));
    wire write_active = mor[0];
    wire map_bit      = mor[1];

    // ---- write strobes: /WE PULSES low while clk is low during a write (rises at posedge to latch
    // with the address/data stable that cycle), and stays HIGH outside a write so it never
    // spuriously re-latches. /OE = write_active holds the SRAM read-output HIGH-Z for the whole
    // write so it cannot fight the write buffer on `io`. (Icarus note: a RUN-time /OE transition on
    // the is61c64 `(oe_n *> io)` modpath asserts in vvp; LDMMU/STMMU run-time writes are therefore
    // exercised only at boot here, where /OE toggles once — the read/translate paths sim cleanly.)
    wire [5:0] wiv;
    (* purpose = "wr_inactive = ~write_active" *)
    sn74ahct04 in1 (.a({5'b0, write_active}), .y(wiv));
    wire wr_inactive = wiv[0];
    wire [3:0] wen;
    (* purpose = "/WE = wr_inactive | clk" *)
    sn74ahct32 or1 (.a({3'b0, wr_inactive}), .b({3'b0, clk}), .y(wen));
    wire we_n = wen[0];

    // ---- table address: boot sweep (loader_addr) vs run index {map_bit, slot} ------------------
    wire [3:0] sram_a;
    (* purpose = "table addr: boot/run" *)
    sn74ahct157 sa (.a({map_bit, addr_logical[15:13]}), .b(loader_addr[3:0]),
                    .sel(loading), .g_n(1'b0), .y(sram_a));

    // ---- write data: boot identity {8'h00, slot=loader[2:0]} vs run entry_in -------------------
    wire [10:0] wdata;
    (* purpose = "write data: identity/entry [3:0]" *)
    sn74ahct157 wd0 (.a(entry_in[3:0]),         .b({1'b0, loader_addr[2:0]}), .sel(loading), .g_n(1'b0), .y(wdata[3:0]));
    (* purpose = "write data: identity/entry [7:4]" *)
    sn74ahct157 wd1 (.a(entry_in[7:4]),         .b(4'b0),                     .sel(loading), .g_n(1'b0), .y(wdata[7:4]));
    wire [3:0] wd2y;
    (* purpose = "write data: identity/entry [10:8]" *)
    sn74ahct157 wd2 (.a({1'b0, entry_in[10:8]}), .b(4'b0),                    .sel(loading), .g_n(1'b0), .y(wd2y));
    assign wdata[10:8] = wd2y[2:0];

    // ---- the table (16x11, padded to DW=16) + write buffer -------------------------------------
    // /OE is tied low (read always enabled) and the write buffer drives the bus only while /WE is
    // LOW: when /WE pulses low the buffer owns `io` (the SRAM is not reading), and at every other
    // time the SRAM drives it — no bus fight, and /OE stays off any specify-path net (an Icarus
    // modpath delay would otherwise assert on the is61c64 `(oe_n *> io)` path).
    wire [15:0] io;
    (* purpose = "table write buf [7:0]" *)
    sn74ahct541 wb0 (.a(wdata[7:0]),          .oe1_n(wr_inactive), .oe2_n(1'b0), .y(io[7:0]));
    (* purpose = "table write buf [15:8]" *)
    sn74ahct541 wb1 (.a({5'b0, wdata[10:8]}), .oe1_n(wr_inactive), .oe2_n(1'b0), .y(io[15:8]));
    (* purpose = "page table (16x11)" *)
    is61c64 #(.AW(4), .DW(16)) tbl (.a(sram_a), .io(io), .ce_n(1'b0), .oe_n(write_active), .we_n(we_n));
    wire [10:0] table_ppn = io[10:0];
    assign entry_rd = table_ppn;

    // ---- DIRECT_PHYSICAL: identity PPN {8'h00, slot} vs the table entry -------------------------
    wire [10:0] ppn;
    (* purpose = "PPN: identity(DIRECT)/table [3:0]" *)
    sn74ahct157 dm0 (.a({1'b0, addr_logical[15:13]}), .b(table_ppn[3:0]), .sel(mmu_addr_n[2]), .g_n(1'b0), .y(ppn[3:0]));
    (* purpose = "PPN: identity/table [7:4]" *)
    sn74ahct157 dm1 (.a(4'b0), .b(table_ppn[7:4]), .sel(mmu_addr_n[2]), .g_n(1'b0), .y(ppn[7:4]));
    wire [3:0] dm2y;
    (* purpose = "PPN: identity/table [10:8]" *)
    sn74ahct157 dm2 (.a(4'b0), .b({1'b0, table_ppn[10:8]}), .sel(mmu_addr_n[2]), .g_n(1'b0), .y(dm2y));
    assign ppn[10:8] = dm2y[2:0];

    // ---- physical address: {PPN, offset} (south-edge wiring) -----------------------------------
    assign a = {ppn, addr_logical[12:0]};
endmodule
`default_nettype wire
