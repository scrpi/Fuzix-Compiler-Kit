// memory_interface — the MDR register and the external memory bus port: the path by which
// the datapath reads and writes main memory. Structural netlist of real chips (R-SIM-1,
// R-SIM-5; hardware.md §2 "Memory interface", §3; interface.md §2-§4).
//
// MDR is the 8-bit data register at the boundary between the 16-bit internal Z bus and the
// 8-bit external data bus `D[7:0]` (hardware.md §2). A 16-bit value crosses as two byte
// cycles (little-endian, D-09); this block is one byte lane.
//
//   * WRITE: a prior microword stages the byte into MDR from Z (Z_DEST=MDR); then MEM_OP=
//     WRITE asserts /WR and MDR drives `D[7:0]`. The device captures on /WR's rising edge
//     (interface.md §4.2). The CPU drives `D` ONLY while /WR is asserted (interface.md §5).
//   * READ:  MEM_OP=READ asserts /RD and floats `D`; the device drives it; MDR captures the
//     byte on the terminating clock edge (interface.md §4.1). The read byte is then on MDR,
//     ready to post on Z (hardware.md §2 "every register write is posted on Z") or drive
//     LEFT (LEFT_SRC=MDR) on a following microword.
//
// Address path (the MMU, §3): a 16-bit logical address — the active one of PC/MAR, selected
// upstream by MMU_ADDR_SRC on the motherboard — is translated to the 24-bit physical address
// on `A[23:0]`. Until the page table lands this is the RESET IDENTITY MAP (low 64 KB logical =
// physical, hardware.md §3 / D-15): `A = {8'h00, addr}` — pure wiring, the spec's power-on
// translation, not a placeholder.
//
// `bus_inhibit` forces /RD//WR idle (and so the write driver off): the integrator ties it to
// `loading`, so no spurious transfer happens during the boot copy, when the control word is
// meaningless (the WCS is mid-write). The standalone bench ties it LOW.
//
// Structure (the BOM):
//   4x sn74ahct157 -> MDR's 8-bit source mux, two 2:1 layers (no inverter — see below):
//                     layer 1 picks Z-low vs MDR-self (Z_DEST=MDR load vs hold);
//                     layer 2 picks external D vs layer-1 (a READ capture overrides).
//   1x sn74ahct32  -> OR `bus_inhibit` into the MEM_OP read/write lines to form /RD//WR.
//   1x sn74ahct574 -> MDR itself (octal D-FF); /OE tied LOW so Q is always live internally.
//   1x sn74ahct541 -> the external write driver: MDR -> D[7:0], enabled by /WR (drive only
//                     during a write — interface.md §5).
//   1x sn74ahct541 -> the LEFT-bus driver: MDR -> LEFT low lane, enabled by LEFT_SRC=MDR.
//
// No-inverter mux trick: each '157 selects A when SEL=0, B when SEL=1, so the active-LOW
// strobes drive SEL directly with A/B ordered so SEL=0 (asserted) picks the load source —
// the same "wire the active-low line straight to select" idiom as the control-store muxes.
//
// SCAFFOLD (hardware.md §2 is tentative; the datapath around this is still landing):
//   - MAR and the Z bus do not exist yet, so `mar`/`z_lo` are driven by the bench; once the
//     register fabric lands they come from the real MAR counter and the Z bus.
//   - /WAIT is honoured by the SEQUENCER (a WAIT microword holds the µPC, microcode.md §2);
//     this block frames a single-edge transfer and does not itself stretch the cycle.
//   - Bus-grant tri-stating of A//RD//WR (interface.md §4.6) is not modelled — no arbiter yet.
//   - MDR's post onto Z on a read is taken off `mdr_q` here; the Z-bus driver is wired when
//     the Z bus exists.
`timescale 1ns/1ps
`default_nettype none
module memory_interface (
    input  wire        clk,

    // --- decoded control (from control_word_decoder), all active LOW --------------
    input  wire [3:0]  mem_op_n,        // MEM_OP one-hot: [0]=IDLE [1]=READ [2]=WRITE
    input  wire        z_dest_mdr_n,    // Z_DEST==MDR  -> capture Z-low into MDR
    input  wire        left_src_mdr_n,  // LEFT_SRC==MDR -> drive MDR onto LEFT low lane
    input  wire        bus_inhibit,     // 1 = force /RD//WR idle (boot copy; = loading)

    // --- internal datapath buses -------------------------------------------------
    input  wire [15:0] addr,            // selected logical address -> MMU (PC/MAR, muxed upstream)
    input  wire [7:0]  z_lo,            // Z bus low byte (the staged write data)
    output wire [7:0]  mdr_q,           // MDR contents — internal tap
    output wire [15:0] z_post,          // read byte posted on Z (3-state, during /RD): {8'h00, D}
    output wire [7:0]  left_lo,         // MDR -> LEFT low lane (3-state; driven by LEFT_SRC=MDR)

    // --- external functional interface (interface.md §2) -------------------------
    output wire [23:0] a,               // physical address A[23:0] (MMU output)
    inout  wire [7:0]  d,               // data bus D[7:0] (CPU drives only while /WR low)
    output wire        rd_n,            // /RD read strobe
    output wire        wr_n             // /WR write strobe
);
    // ---- transfer strobes: MEM_OP one-hot, OR'd with bus_inhibit ----------------
    // mem_op_n is active-low one-hot, so its READ/WRITE lines are the un-inhibited strobes;
    // OR bus_inhibit in so the boot copy (or any inhibit) forces both HIGH (idle), which
    // also disables the write driver below (its enable is wr_n). IDLE leaves both HIGH.
    wire [3:0] strobe;
    (* purpose = "/RD//WR = MEM_OP | bus_inhibit" *)
    sn74ahct32 strobes (.a({2'b00, mem_op_n[2], mem_op_n[1]}), .b({4{bus_inhibit}}), .y(strobe));
    assign rd_n = strobe[0];
    assign wr_n = strobe[1];

    // ---- MMU: reset identity map (low 64 KB logical = physical) -----------------
    assign a = {8'h00, addr};

    // ---- MDR source mux: {external D on READ, Z-low on Z_DEST=MDR, else hold} ----
    // Layer 1: SEL = z_dest_mdr_n -> asserted (LOW) picks A = z_lo (load); else B = mdr_q.
    wire [7:0] src1;
    (* purpose = "MDR src mux L1 [3:0] (Z-low / hold)" *)
    sn74ahct157 m1lo (.a(z_lo[3:0]), .b(mdr_q[3:0]), .sel(z_dest_mdr_n), .g_n(1'b0), .y(src1[3:0]));
    (* purpose = "MDR src mux L1 [7:4] (Z-low / hold)" *)
    sn74ahct157 m1hi (.a(z_lo[7:4]), .b(mdr_q[7:4]), .sel(z_dest_mdr_n), .g_n(1'b0), .y(src1[7:4]));

    // Layer 2: SEL = rd_n -> asserted (LOW) picks A = external D (capture); else B = layer 1.
    wire [7:0] dsrc;
    (* purpose = "MDR src mux L2 [3:0] (ext-D / L1)" *)
    sn74ahct157 m2lo (.a(d[3:0]), .b(src1[3:0]), .sel(rd_n), .g_n(1'b0), .y(dsrc[3:0]));
    (* purpose = "MDR src mux L2 [7:4] (ext-D / L1)" *)
    sn74ahct157 m2hi (.a(d[7:4]), .b(src1[7:4]), .sel(rd_n), .g_n(1'b0), .y(dsrc[7:4]));

    // ---- MDR register: captures dsrc each edge; /OE LOW so Q is always live ------
    (* purpose = "MDR (memory data register)" *)
    sn74ahct574 mdr (.Q(mdr_q), .D(dsrc), .CLK(clk), .OE_n(1'b0));

    // ---- external write driver: MDR -> D[7:0], enabled only while /WR asserted ---
    (* purpose = "MDR -> D[7:0] write driver" *)
    sn74ahct541 wdrv (.a(mdr_q), .oe1_n(wr_n), .oe2_n(1'b0), .y(d));

    // ---- LEFT-bus driver: MDR -> LEFT low lane, enabled by LEFT_SRC=MDR ----------
    (* purpose = "MDR -> LEFT low-lane driver" *)
    sn74ahct541 ldrv (.a(mdr_q), .oe1_n(left_src_mdr_n), .oe2_n(1'b0), .y(left_lo));

    // ---- read-byte -> Z post (the combinational bypass; microcode-source.md §13) ----------
    // A read posts its byte on Z *during* the read so a named Z_DEST + the flags capture it in
    // the same microword (parallel capture, NOT the registered/stale mdr_q). Source the LIVE pad
    // `d` — the same byte MDR is simultaneously capturing — gated by /RD; zero-extend Z[15:8].
    (* purpose = "read byte -> Z[7:0]" *)
    sn74ahct541 zdrv  (.a(d),     .oe1_n(rd_n), .oe2_n(1'b0), .y(z_post[7:0]));
    (* purpose = "read zero-ext -> Z[15:8]" *)
    sn74ahct541 zdrvh (.a(8'h00), .oe1_n(rd_n), .oe2_n(1'b0), .y(z_post[15:8]));
endmodule
`default_nettype wire
