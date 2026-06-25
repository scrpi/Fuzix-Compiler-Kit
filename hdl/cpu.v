// cpu — BLIP top-level (SCAFFOLD). Boots its microcode, then runs. Self-contained on the
// control-store side (its own boot EEPROM + WCS); the SYSTEM BUS (A/D//RD//WR) leaves the CPU
// so the testbench can attach a memory model outside the CPU under test (R-SIM-3).
//
// `loading` IS the boot/run state (no separate FSM). loading=1 (BOOT): the loader copies the
// EEPROM into the WCS; the µPC is held at 0; the registers are held cleared and CC at its reset
// value; the memory bus is inhibited. loading=0 (RUN): the µPC walks the store and the datapath
// runs. A system reset re-runs the copy.
//
// THE DATAPATH (hardware.md §2): three buses join the registers and the ALU —
//   LEFT  : any register can drive it (PC/MAR/SCR1/SCR2/MDR here) -> the ALU left input.
//   RIGHT : the two scratch registers + the constant generator (right_bus) -> the ALU right.
//   Z     : the ALU result; any register latches from it (PC/MAR/SCR via *_CTRL/Z_DEST load).
// The ALU computes LEFT op RIGHT, its flags feed CC, and CC's carry feeds back to the ALU; CC
// also derives the branch microconditions the sequencer selects. A real fetch (PC -> MMU ->
// memory -> MDR -> IR -> DISPATCH) and a real branch (compute -> CC -> condition) both run.
//
// Blocks: uc_loader (boot) · microsequencer (µPC) · register16 x4 (PC/MAR/SCR1/SCR2, D-36) ·
//   right_bus (RIGHT mux + const-gen) · alu (LEFT op RIGHT -> Z + flags) · cc (CC + conditions)
//   · memory_interface (MDR + bus) · IR · microcode_store + opcode_lut · control_word_decoder.
//
// DEBUG injects (R-DBG-5), used by the unit benches, real otherwise:
//   ir_inject   1 -> IR from ir_drive (microsequencer bench); 0 -> real fetch (IR <- MDR).
//   cond_inject 1 -> all 16 sequencer conditions from cond_drive; 0 -> the CC-derived
//               conditions cond[6:0] come from CC (real branches), cond[15:7] still injected
//               (the internal conditions IRQ/ULOOP/… are not built yet).
//
// SCAFFOLD — byte-lane steering and the rest of the register file are NOT built yet, so the
// directed unit tests (full-16 loads, 8-bit-low compute) run but the production blip.uc, which
// uses the byte lanes for memory operands, does not yet:
//   * LEFT_LANE (FULL16/LOW/SIGN_EXT/HIGH_TO_LOW) is decoded but unwired — MDR drives only
//     LEFT[7:0]; LEFT[15:8] floats when MDR is the source (a 16-bit op on a byte operand is
//     wrong until a lane-steer block sign-extends/zeroes the high byte onto LEFT).
//   * Z_LANE (FULL16/LOW/HIGH) is decoded but unwired — every register here loads FULL16
//     (load_lo_n = load_hi_n), so a per-byte Z_DEST (e.g. the A:B accumulator lanes) is not yet
//     honoured.
//   * The D/X/Y/USP/SSP registers and the internal microconditions (IRQ/NMI/ULOOP/…) are absent;
//     an unbuilt LEFT_SRC code leaves LEFT floating, and cond[15:8] still come from cond_drive.
`timescale 1ns/1ps
`default_nettype none
module cpu #(
    parameter FILE = ""              // the microcode image (burned into the loader's EEPROM)
) (
    input  wire         clk,
    input  wire         rst_n,       // active-low power-on reset
    // privileged debug interface (R-DBG-5)
    input  wire         ir_inject,   // 1 = force IR from ir_drive; 0 = real fetch (IR<-MDR)
    input  wire [7:0]   ir_drive,    // debug opcode deposit (used when ir_inject)
    input  wire         cond_inject, // 1 = all conditions from cond_drive; 0 = CC drives cond[6:0]
    input  wire [15:0]  cond_drive,  // injected microconditions (all when cond_inject, else [15:7])
    // system bus — memory is modelled in the harness (R-SIM-3; interface.md §2)
    output wire [23:0]  a,           // physical address A[23:0]
    inout  wire [7:0]   d,           // data bus D[7:0]
    output wire         rd_n,        // /RD
    output wire         wr_n,        // /WR
    // observability — privileged debug taps (R-DBG-5)
    output wire         loading,     // HIGH while the boot copy runs
    output wire [11:0]  upc,         // the micro-PC once running
    output wire [87:0]  cw,          // the 88-bit control word read from the WCS
    output wire [11:0]  lut_out,     // opcode-LUT dispatch target {lut_hi[3:0], lut_lo}
    output wire [7:0]   ir_q,        // IR contents (the dispatch index)
    output wire [15:0]  pc_q,        // PC contents
    output wire [15:0]  z_q,         // the Z bus (ALU result)
    output wire [7:0]   cc_q         // the CC register (M - H I N Z V C)
);
    localparam NSEG  = 13;           // 11 WCS + 2 opcode-LUT

    wire [11:0]     loader_addr;
    wire [7:0]      loader_wdata;
    wire [NSEG-1:0] cs_sel_n;
    wire            run;
    wire [87:0]     cw_wcs;

    // --- boot loader -------------------------------------------------------
    (* purpose = "microcode loader" *)
    uc_loader #(.FILE(FILE)) loader (
        .clk(clk), .rst_n(rst_n),
        .sram_addr(loader_addr), .sram_wdata(loader_wdata),
        .cs_n(cs_sel_n), .loading(loading)
    );

    // --- control-word decoder: datapath section -> one-hot strobes ----------
    wire [3:0]  ir_load_n;
    wire [15:0] left_src_n, z_dest_n, alu_op_n;
    wire [7:0]  alu_shift_n, right_src_n;
    wire [3:0]  pc_ctrl_n, mar_ctrl_n, mem_op_n, mmu_addr_n;
    wire [3:0]  v_src_n, c_src_n, cc_write_n, cc_mi_n;
    wire [4:0]  flag_we;
    wire        alu_cin, alu_width, z_accum;
    (* purpose = "datapath decoder" *)
    control_word_decoder dec (
        .cw_dp(cw_wcs[87:24]),
        .ir_load_n(ir_load_n), .left_src_n(left_src_n), .right_src_n(right_src_n),
        .alu_op_n(alu_op_n), .alu_shift_n(alu_shift_n), .alu_cin(alu_cin), .alu_width(alu_width),
        .flag_we(flag_we), .v_src_n(v_src_n), .c_src_n(c_src_n), .z_accum(z_accum),
        .cc_write_n(cc_write_n), .cc_mi_n(cc_mi_n), .z_dest_n(z_dest_n),
        .pc_ctrl_n(pc_ctrl_n), .mar_ctrl_n(mar_ctrl_n),
        .mem_op_n(mem_op_n), .mmu_addr_n(mmu_addr_n)
    );

    // --- run = ~loading, plus the PC/MAR COUNT-enable inversions ------------
    wire [5:0] inv_y;
    (* purpose = "run=~loading; PC/MAR count enables" *)
    sn74ahct04 inv (.a({3'b000, mar_ctrl_n[2], pc_ctrl_n[2], loading}), .y(inv_y));
    assign run          = inv_y[0];
    wire   pc_count_en  = inv_y[1];
    wire   mar_count_en = inv_y[2];

    // --- reg/CC reset = rst_n & run (held through the boot copy) ------------
    wire [3:0] and_y;
    (* purpose = "reg reset = rst_n & run" *)
    sn74ahct08 rstgate (.a({3'b000, rst_n}), .b({3'b000, run}), .y(and_y));
    wire reg_reset_n = and_y[0];

    // --- the three datapath buses ------------------------------------------
    // LEFT and Z are shared, tri-state (wired-OR of the register/ALU drivers). RIGHT is local
    // to the ALU board (right_bus). Z is driven by the ALU; the registers latch from it.
    wire [15:0] left, right, z;
    wire [7:0]  mdr_q;
    assign z_q = z;

    // --- PC, MAR, SCR1, SCR2: four universal '163-counter register boards ---
    wire [15:0] pc_w, mar_w, scr1_w, scr2_w;
    (* purpose = "PC register" *)
    register16 pc_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(pc_ctrl_n[1]), .load_hi_n(pc_ctrl_n[1]),
        .count_en(pc_count_en), .drive_left_n(left_src_n[6]), .q(pc_w), .left_out(left)
    );
    (* purpose = "MAR register" *)
    register16 mar_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(mar_ctrl_n[1]), .load_hi_n(mar_ctrl_n[1]),
        .count_en(mar_count_en), .drive_left_n(left_src_n[7]), .q(mar_w), .left_out(left)
    );
    // Scratch registers: latch from Z on Z_DEST=SCR1/SCR2 (full16), never count, drive LEFT.
    (* purpose = "SCR1 register" *)
    register16 scr1 (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(z_dest_n[5]), .load_hi_n(z_dest_n[5]),
        .count_en(1'b0), .drive_left_n(left_src_n[8]), .q(scr1_w), .left_out(left)
    );
    (* purpose = "SCR2 register" *)
    register16 scr2 (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(z_dest_n[6]), .load_hi_n(z_dest_n[6]),
        .count_en(1'b0), .drive_left_n(left_src_n[9]), .q(scr2_w), .left_out(left)
    );
    assign pc_q = pc_w;

    // --- RIGHT bus: scratch registers + constant generator -----------------
    (* purpose = "RIGHT bus (SCR + const-gen)" *)
    right_bus rb (.scr1(scr1_w), .scr2(scr2_w), .right_src_n(right_src_n), .right(right));

    // --- ALU: LEFT op RIGHT -> Z, with the flags to CC ---------------------
    wire fn, fz, fv, fc, fh;
    (* purpose = "ALU" *)
    alu u_alu (
        .left(left), .right(right), .alu_op_n(alu_op_n), .alu_shift_n(alu_shift_n),
        .alu_cin(alu_cin), .alu_width(alu_width), .cc_c(cc_q[0]),
        .z(z), .flag_n(fn), .flag_z(fz), .flag_v(fv), .flag_c(fc), .flag_h(fh)
    );

    // --- CC: latch the flags, derive the branch conditions -----------------
    wire        cc_m;
    wire [6:0]  cc_cond;
    (* purpose = "CC (flags + conditions)" *)
    cc u_cc (
        .clk(clk), .reset_n(reg_reset_n),
        .flag_n(fn), .flag_z(fz), .flag_v(fv), .flag_c(fc), .flag_h(fh),
        .flag_we(flag_we), .v_src_n(v_src_n), .c_src_n(c_src_n), .z_accum(z_accum),
        .cc_write_n(cc_write_n), .cc_mi_n(cc_mi_n), .z_lo(z[7:0]),
        .cc_q(cc_q), .cc_m(cc_m), .cond(cc_cond)
    );

    // --- address mux: PC vs MAR onto the MMU per MMU_ADDR_SRC ---------------
    wire [15:0] addr_logical;
    (* purpose = "addr mux PC/MAR [3:0]" *)
    sn74ahct157 am0 (.a(pc_w[3:0]),   .b(mar_w[3:0]),   .sel(mmu_addr_n[1]), .g_n(1'b0), .y(addr_logical[3:0]));
    (* purpose = "addr mux PC/MAR [7:4]" *)
    sn74ahct157 am1 (.a(pc_w[7:4]),   .b(mar_w[7:4]),   .sel(mmu_addr_n[1]), .g_n(1'b0), .y(addr_logical[7:4]));
    (* purpose = "addr mux PC/MAR [11:8]" *)
    sn74ahct157 am2 (.a(pc_w[11:8]),  .b(mar_w[11:8]),  .sel(mmu_addr_n[1]), .g_n(1'b0), .y(addr_logical[11:8]));
    (* purpose = "addr mux PC/MAR [15:12]" *)
    sn74ahct157 am3 (.a(pc_w[15:12]), .b(mar_w[15:12]), .sel(mmu_addr_n[1]), .g_n(1'b0), .y(addr_logical[15:12]));

    // --- MDR + external bus port. MDR drives LEFT (low lane); write data = Z low. ---
    (* purpose = "MDR + memory bus port" *)
    memory_interface mi (
        .clk(clk),
        .mem_op_n(mem_op_n), .z_dest_mdr_n(z_dest_n[7]), .left_src_mdr_n(left_src_n[10]),
        .bus_inhibit(loading),
        .addr(addr_logical), .z_lo(z[7:0]),
        .mdr_q(mdr_q), .left_lo(left[7:0]),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n)
    );

    // --- opcode register IR: latch from MDR on IR_LOAD, or from ir_drive (debug) --
    wire [7:0] ir, ir_inner, ir_d;
    (* purpose = "IR src: MDR vs hold [3:0]" *)
    sn74ahct157 iri0 (.a(mdr_q[3:0]), .b(ir[3:0]), .sel(ir_load_n[1]), .g_n(1'b0), .y(ir_inner[3:0]));
    (* purpose = "IR src: MDR vs hold [7:4]" *)
    sn74ahct157 iri1 (.a(mdr_q[7:4]), .b(ir[7:4]), .sel(ir_load_n[1]), .g_n(1'b0), .y(ir_inner[7:4]));
    (* purpose = "IR src: inject vs fetch [3:0]" *)
    sn74ahct157 iro0 (.a(ir_inner[3:0]), .b(ir_drive[3:0]), .sel(ir_inject), .g_n(1'b0), .y(ir_d[3:0]));
    (* purpose = "IR src: inject vs fetch [7:4]" *)
    sn74ahct157 iro1 (.a(ir_inner[7:4]), .b(ir_drive[7:4]), .sel(ir_inject), .g_n(1'b0), .y(ir_d[7:4]));
    (* purpose = "opcode register IR" *)
    sn74ahct574 ir_reg (.Q(ir), .D(ir_d), .CLK(clk), .OE_n(1'b0));
    assign ir_q = ir;

    // --- condition lines into the sequencer --------------------------------
    // cond[6:0] = cond_inject ? cond_drive[6:0] : CC ; cond[15:7] = cond_drive (internal conds).
    // cci1's 4th lane is a dead net so bit 7 has a SINGLE driver (the assign) — no bus short.
    wire [15:0] cond_seq;
    wire [3:0]  cci1_y;
    (* purpose = "cond mux CC vs inject [3:0]" *)
    sn74ahct157 cci0 (.a(cc_cond[3:0]), .b(cond_drive[3:0]), .sel(cond_inject), .g_n(1'b0), .y(cond_seq[3:0]));
    (* purpose = "cond mux CC vs inject [6:4]" *)
    sn74ahct157 cci1 (.a({1'b0, cc_cond[6:4]}), .b({1'b0, cond_drive[6:4]}), .sel(cond_inject), .g_n(1'b0), .y(cci1_y));
    assign cond_seq[6:4]  = cci1_y[2:0];
    assign cond_seq[7]    = cond_drive[7];      // TRUE slot (forced in the sequencer anyway)
    assign cond_seq[15:8] = cond_drive[15:8];   // internal microconditions (not built yet)

    // --- microsequencer ----------------------------------------------------
    wire [11:0] lut_data;
    (* purpose = "micro-sequencer (next uPC)" *)
    microsequencer useq (
        .clk(clk), .clr_n(run),
        .useq_op(cw_wcs[2:0]), .next_addr(cw_wcs[14:3]),
        .ucond_sel(cw_wcs[18:15]), .ucond_pol(cw_wcs[19]),
        .cond(cond_seq), .lut_data(lut_data), .upc(upc)
    );

    // --- control store + opcode LUT ----------------------------------------
    wire [7:0]  lut_lo, lut_hi;
    (* purpose = "WCS (88-bit control word)" *)
    microcode_store #(.NWCS(11)) store (
        .clk(clk), .upc(upc), .loader_addr(loader_addr), .loading(loading),
        .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .cs_n(cs_sel_n[10:0]), .cw(cw_wcs)
    );
    (* purpose = "opcode LUT (dispatch)" *)
    opcode_lut lut (
        .clk(clk), .loader_addr(loader_addr), .dispatch_page(cw_wcs[22]), .ir(ir), .loading(loading),
        .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .cs_n(cs_sel_n[12:11]), .lut_lo(lut_lo), .lut_hi(lut_hi)
    );

    assign cw       = cw_wcs;
    assign lut_data = {lut_hi[3:0], lut_lo};
    assign lut_out  = lut_data;
endmodule
`default_nettype wire
