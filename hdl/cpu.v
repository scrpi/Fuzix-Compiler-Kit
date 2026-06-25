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
//   cond_inject 1 -> all 16 sequencer conditions from cond_drive; 0 -> the real conditions:
//               cond[6:0] from CC (branches) and cond[15:8] from the internal microconditions
//               ([8]=ULOOP, [9]=IRQ, [10]=NMI, [11]=WAIT_READY).
//
// Byte-lane steering is built (D-09 byte-cycle path; cpu-physical-construction.md §6.4(a)):
//   * LEFT_LANE (FULL16/LOW/SIGN_EXT/HIGH_TO_LOW) — left_lane steers the raw LEFT bus into the
//     ALU's LEFT input, so a byte operand (e.g. from MDR) is zero-/sign-extended or moved off the
//     high lane before it enters the ALU; LEFT[15:8] no longer floats when MDR is the source.
//   * Z_LANE (FULL16/LOW/HIGH) — z_lane promotes Z[7:0] onto the high byte and gates the SCR
//     /load-low and /load-high strobes, so a 16-bit value can land as two byte cycles.
//
// The full register file is built: D (A:B, byte-lane-gated), X/Y (off-bus +1 counters), USP/SSP
// reached either explicitly or as the bank-resolved ACTIVE_SP (sp_bank); and the LEFT sources CC,
// IR_IMM and MMU_ENTRY. The internal microconditions ULOOP/IRQ/NMI/WAIT_READY are wired into
// cond[11:8]; the sequencer now runs the production blip.uc with no condition injection.
//
// A memory read POSTS its byte on Z during /RD (memory_interface zdrv; the combinational bypass),
// so a read-into-register (`reg <- [PC]`, the LD/operand-fetch idiom) latches it + the flags in
// one microword; the ALU PASS_L Z drive is suppressed during a read so it can't fight the post.
// FETCH is single-cycle: IR latches the read byte and the opcode-LUT is indexed by the next-IR
// value (ir_d), so `IR <- [PC]; PC++; dispatch` fetches and dispatches in one word. The real
// blip.uc runs end-to-end (sim/tb/prog).
//
// The MMU is built (mmu.v): an 8 KB-page translate (offset pass-through, 8-slot index, 11-bit PPN
// -> A[23:13]) over a 16x11 page table that boots to the identity map, with MMU_MAP_SEL (kernel/
// user/force), DIRECT_PHYSICAL, and LDMMU/STMMU entry write/read-back. (Icarus note: the is61c64's
// bidirectional bus + -gspecify limits RUN-time LDMMU writes in sim to the boot-identity path.)
//
// The trap-vector encoder (trap_encoder.v) intercepts RETURN_FETCH: a pending NMI/IRQ redirects the
// µPC to that trap's fixed microroutine entry (NMI > IRQ); IRQ is hardware-masked by CC.I
// (irq_masked = irq & ~CC.I feeds both cond[9] and the encoder). NMI is taken as a level (the
// edge-latch is a refinement). The trap microroutine bodies in blip.uc + a .trap address-pin
// directive are the remaining microcode-side work.
//
// The bus arbiter (bus_arbiter.v) grants the bus on /BUSREQ (tri-stating A//RD//WR via the south-
// edge buffers, inhibiting the CPU's own transfers); TAS_LOCK holds the bus across an RMW so the
// grant is refused mid-lock. /BUSGRANT leaves the CPU.
//
// SCAFFOLD — what remains:
//   * cond[12]=MULTIBYTE_LAST ties inactive (its counter is unbuilt; under-specified). The
//     trap encoder does not yet take illegal/priv as sync sources (they need a dispatch-time
//     redirect + a current-page register for page-1 opcodes) — cond[13]/[14] are live conditions.
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
    input  wire         cond_inject, // 1 = all conditions from cond_drive; 0 = CC/internal conds
    input  wire [15:0]  cond_drive,  // injected microconditions (used when cond_inject)
    // external interrupt / bus microcondition lines (interface.md; sequencer cond[10:9],[11])
    input  wire         irq,         // IRQ request pending (level; I-mask gating is microcode policy)
    input  wire         nmi,         // NMI request pending (non-maskable)
    input  wire         wait_ready,  // bus ready (1 = ready; 0 = stretch the cycle)
    input  wire         busreq_n,    // /BUSREQ — an external master asks for the bus (interface.md §4.6)
    output wire         busgrant_n,  // /BUSGRANT — the CPU has tri-stated A//RD//WR
    // system bus — memory is modelled in the harness (R-SIM-3; interface.md §2)
    output wire [23:0]  a,           // physical address A[23:0] (tri-state on bus grant)
    inout  wire [7:0]   d,           // data bus D[7:0]
    output wire         rd_n,        // /RD (tri-state on bus grant)
    output wire         wr_n,        // /WR (tri-state on bus grant)
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
    wire [3:0]  ir_load_n, left_lane_n, z_lane_n;
    wire [15:0] left_src_n, z_dest_n, alu_op_n;
    wire [7:0]  alu_shift_n, right_src_n;
    wire [3:0]  pc_ctrl_n, mar_ctrl_n, x_ctrl_n, y_ctrl_n, mem_op_n;
    wire [3:0]  mmu_addr_n, mmu_map_n, mmu_pt_n;
    wire [3:0]  v_src_n, c_src_n, cc_write_n, cc_mi_n;
    wire [4:0]  flag_we;
    wire        alu_cin, alu_width, z_accum, sp_bank, tas_lock;
    (* purpose = "datapath decoder" *)
    control_word_decoder dec (
        .cw_dp(cw_wcs[87:24]),
        .ir_load_n(ir_load_n), .left_src_n(left_src_n), .left_lane_n(left_lane_n),
        .right_src_n(right_src_n),
        .alu_op_n(alu_op_n), .alu_shift_n(alu_shift_n), .alu_cin(alu_cin), .alu_width(alu_width),
        .flag_we(flag_we), .v_src_n(v_src_n), .c_src_n(c_src_n), .z_accum(z_accum),
        .cc_write_n(cc_write_n), .cc_mi_n(cc_mi_n), .z_dest_n(z_dest_n), .z_lane_n(z_lane_n),
        .pc_ctrl_n(pc_ctrl_n), .mar_ctrl_n(mar_ctrl_n), .x_ctrl_n(x_ctrl_n), .y_ctrl_n(y_ctrl_n),
        .mem_op_n(mem_op_n), .mmu_addr_n(mmu_addr_n), .mmu_map_n(mmu_map_n),
        .mmu_pt_n(mmu_pt_n), .sp_bank(sp_bank), .tas_lock(tas_lock)
    );

    // --- bus arbiter: /BUSREQ -> /BUSGRANT; TAS_LOCK holds the bus across an RMW ---
    wire granted, bus_oe_n;
    (* purpose = "bus arbiter (/BUSREQ-/BUSGRANT)" *)
    bus_arbiter u_arb (
        .clk(clk), .busreq_n(busreq_n), .bus_locked(tas_lock), .loading(loading),
        .granted(granted), .busgrant_n(busgrant_n), .bus_oe_n(bus_oe_n)
    );
    // the CPU inhibits its own transfers while booting OR while the bus is granted away
    wire [3:0] inhib;
    (* purpose = "bus_inhibit = loading | granted" *)
    sn74ahct32 inhg (.a({3'b0, loading}), .b({3'b0, granted}), .y(inhib));
    wire bus_inhibit = inhib[0];

    // --- run = ~loading, plus the PC/MAR/X/Y COUNT-enable inversions; rd = ~/RD --------
    // `rd` derives from the INTERNAL read strobe mi_rd_n (memory_interface's pre-tri-state /RD),
    // NEVER from the external `rd_n` pin: that pin is tri-stated on a bus grant (rwdrv below), so
    // ~rd_n would be X and X-poison the ALU PASS_L enable -> the Z bus. mi_rd_n is forced HIGH/idle
    // by bus_inhibit during a grant, so rd=0 and Z stays defined (R-IF-4; review-confirmed).
    wire mi_rd_n, mi_wr_n;               // memory_interface's pre-tri-state /RD //WR (declared early)
    wire [5:0] inv_y;
    (* purpose = "run=~loading; PC/MAR/X/Y count enables; rd=~mi_rd_n" *)
    sn74ahct04 inv (.a({y_ctrl_n[2], x_ctrl_n[2], mar_ctrl_n[2], pc_ctrl_n[2], loading, mi_rd_n}), .y(inv_y));
    wire   rd           = inv_y[0];      // read active-high (suppress the ALU PASS_L Z drive)
    assign run          = inv_y[1];
    wire   pc_count_en  = inv_y[2];
    wire   mar_count_en = inv_y[3];
    wire   x_count_en   = inv_y[4];
    wire   y_count_en   = inv_y[5];

    // A bare read microword leaves ALU_OP=PASS_L (default), which would drive the floating LEFT
    // onto Z[7:0] and fight the read-byte post. Force the ALU's PASS_L enable HIGH during a read
    // (the read byte then owns Z); every non-read microword is unchanged.
    wire [3:0] passl;
    (* purpose = "ALU PASS_L /enable | read-active" *)
    sn74ahct32 passlblk (.a({3'b000, alu_op_n[0]}), .b({3'b000, rd}), .y(passl));
    wire alu_passl_n = passl[0];

    // --- reg/CC reset = rst_n & run (held through the boot copy) ------------
    wire [3:0] and_y;
    (* purpose = "reg reset = rst_n & run" *)
    sn74ahct08 rstgate (.a({3'b000, rst_n}), .b({3'b000, run}), .y(and_y));
    wire reg_reset_n = and_y[0];

    // --- the three datapath buses ------------------------------------------
    // LEFT_RAW and Z are shared, tri-state (wired-OR of the register/MDR drivers). The LEFT_LANE
    // steer maps LEFT_RAW -> the ALU's LEFT input (widen a byte / move the high byte down). The
    // Z_LANE steer maps Z -> Z_LOAD (byte-promote on a HIGH-lane latch). RIGHT is local to the
    // ALU board (right_bus). Z is driven by the ALU; the registers latch from Z_LOAD.
    wire [15:0] left_raw, left, right, z, z_load;
    wire        z_block_lo, z_block_hi;       // Z_LANE lane suppressors (active HIGH)
    wire        cc_m;                         // CC.M (supervisor) — used by sp_bank / conditions
    wire [7:0]  mdr_q;
    assign z_q = z;

    // --- LEFT_LANE steer: widen/move the operand entering the ALU ----------
    (* purpose = "LEFT_LANE steer (widen)" *)
    left_lane u_left_lane (.left_raw(left_raw), .left_lane_n(left_lane_n), .left(left));

    // --- Z_LANE steer: high-byte promote + per-lane load suppressors -------
    (* purpose = "Z_LANE steer (byte lanes)" *)
    z_lane u_z_lane (.z(z), .z_lane_n(z_lane_n), .z_load(z_load),
                     .block_lo(z_block_lo), .block_hi(z_block_hi));

    // SCR1/SCR2 latch from Z_LOAD; their per-byte /load strobes are the Z_DEST strobe OR'd with
    // the Z_LANE blocker (HIGH suppresses the low byte, LOW the high byte). FULL16 blocks
    // neither, so both bytes load — identical to a plain Z_DEST=SCRn latch.
    wire [3:0] scr_ld_n;        // {scr2_hi, scr2_lo, scr1_hi, scr1_lo}
    (* purpose = "SCR1/SCR2 /load = Z_DEST | Z_LANE-block" *)
    sn74ahct32 scrld (.a({z_dest_n[6], z_dest_n[6], z_dest_n[5], z_dest_n[5]}),
                      .b({z_block_hi, z_block_lo, z_block_hi, z_block_lo}), .y(scr_ld_n));

    // --- PC, MAR, SCR1, SCR2: four universal '163-counter register boards ---
    // PC/MAR load full16 from Z (a LOAD captures a 16-bit address; Z_LANE does not apply).
    wire [15:0] pc_w, mar_w, scr1_w, scr2_w;
    (* purpose = "PC register" *)
    register16 pc_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(pc_ctrl_n[1]), .load_hi_n(pc_ctrl_n[1]),
        .count_en(pc_count_en), .drive_left_n(left_src_n[6]), .q(pc_w), .left_out(left_raw)
    );
    (* purpose = "MAR register" *)
    register16 mar_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(mar_ctrl_n[1]), .load_hi_n(mar_ctrl_n[1]),
        .count_en(mar_count_en), .drive_left_n(left_src_n[7]), .q(mar_w), .left_out(left_raw)
    );
    // Scratch registers: latch from Z_LOAD on Z_DEST=SCR1/SCR2 (lane-gated), never count, drive LEFT.
    (* purpose = "SCR1 register" *)
    register16 scr1 (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z_load),
        .load_lo_n(scr_ld_n[0]), .load_hi_n(scr_ld_n[1]),
        .count_en(1'b0), .drive_left_n(left_src_n[8]), .q(scr1_w), .left_out(left_raw)
    );
    (* purpose = "SCR2 register" *)
    register16 scr2 (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z_load),
        .load_lo_n(scr_ld_n[2]), .load_hi_n(scr_ld_n[3]),
        .count_en(1'b0), .drive_left_n(left_src_n[9]), .q(scr2_w), .left_out(left_raw)
    );
    assign pc_q = pc_w;

    // --- the rest of the architectural register file (hardware.md §2) -------
    // D (=A:B accumulator): latches from Z_LOAD on Z_DEST=D, byte-lane-gated exactly like the
    // scratch regs (A=low, B=high) so 8-bit accumulator ops land in one lane. X/Y are off-bus
    // +1 counters (load full16 / COUNT / hold, D-36). USP/SSP are plain full16 registers; the
    // active one is reached as ACTIVE_SP, bank-resolved by sp_bank below. None drives RIGHT.
    wire [15:0] d_w, x_w, y_w, usp_w, ssp_w;
    wire [3:0]  d_ld_n;        // {_, _, d_hi, d_lo}
    (* purpose = "D /load = Z_DEST=D | Z_LANE-block" *)
    sn74ahct32 dld (.a({2'b00, z_dest_n[1], z_dest_n[1]}),
                    .b({2'b00, z_block_hi, z_block_lo}), .y(d_ld_n));
    (* purpose = "D register (A:B accumulator)" *)
    register16 d_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z_load),
        .load_lo_n(d_ld_n[0]), .load_hi_n(d_ld_n[1]),
        .count_en(1'b0), .drive_left_n(left_src_n[1]), .q(d_w), .left_out(left_raw)
    );
    (* purpose = "X register (counter)" *)
    register16 x_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(x_ctrl_n[1]), .load_hi_n(x_ctrl_n[1]),
        .count_en(x_count_en), .drive_left_n(left_src_n[2]), .q(x_w), .left_out(left_raw)
    );
    (* purpose = "Y register (counter)" *)
    register16 y_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(y_ctrl_n[1]), .load_hi_n(y_ctrl_n[1]),
        .count_en(y_count_en), .drive_left_n(left_src_n[3]), .q(y_w), .left_out(left_raw)
    );
    // USP/SSP: bank-resolved drive/load from sp_bank (explicit USP/SSP OR ACTIVE_SP). Full16, no count.
    wire usp_drive_n, ssp_drive_n, usp_load_n, ssp_load_n;
    (* purpose = "ACTIVE_SP bank resolver" *)
    sp_bank u_sp_bank (
        .cc_m(cc_m), .sp_bank(sp_bank),
        .left_active_sp_n(left_src_n[14]), .left_usp_n(left_src_n[4]), .left_ssp_n(left_src_n[5]),
        .z_active_sp_n(z_dest_n[4]), .z_usp_n(z_dest_n[2]), .z_ssp_n(z_dest_n[3]),
        .usp_drive_n(usp_drive_n), .ssp_drive_n(ssp_drive_n),
        .usp_load_n(usp_load_n), .ssp_load_n(ssp_load_n)
    );
    (* purpose = "USP register (user SP)" *)
    register16 usp_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(usp_load_n), .load_hi_n(usp_load_n),
        .count_en(1'b0), .drive_left_n(usp_drive_n), .q(usp_w), .left_out(left_raw)
    );
    (* purpose = "SSP register (supervisor SP)" *)
    register16 ssp_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(ssp_load_n), .load_hi_n(ssp_load_n),
        .count_en(1'b0), .drive_left_n(ssp_drive_n), .q(ssp_w), .left_out(left_raw)
    );

    // --- RIGHT bus: scratch registers + constant generator -----------------
    (* purpose = "RIGHT bus (SCR + const-gen)" *)
    right_bus rb (.scr1(scr1_w), .scr2(scr2_w), .right_src_n(right_src_n), .right(right));

    // --- ALU: LEFT op RIGHT -> Z, with the flags to CC ---------------------
    wire fn, fz, fv, fc, fh;
    (* purpose = "ALU" *)
    alu u_alu (
        .left(left), .right(right), .alu_op_n({alu_op_n[15:1], alu_passl_n}), .alu_shift_n(alu_shift_n),
        .alu_cin(alu_cin), .alu_width(alu_width), .cc_c(cc_q[0]),
        .z(z), .flag_n(fn), .flag_z(fz), .flag_v(fv), .flag_c(fc), .flag_h(fh)
    );

    // --- CC: latch the flags, derive the branch conditions -----------------
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

    // --- MMU: translate the logical address to A[23:0] (owns the address bus) ---
    wire [15:0] mmu_entry_q;
    wire [10:0] mmu_entry_rd;
    wire [23:0] a_pre;
    (* purpose = "MMU (translate + page table)" *)
    mmu u_mmu (
        .clk(clk), .loading(loading), .loader_addr(loader_addr), .addr_logical(addr_logical),
        .mmu_addr_n(mmu_addr_n), .mmu_map_n(mmu_map_n), .mmu_pt_n(mmu_pt_n), .cc_m(cc_m),
        .entry_in(mmu_entry_q[10:0]), .entry_rd(mmu_entry_rd), .a(a_pre)
    );
    // A[23:0] south-edge drivers — tri-stated on a bus grant (interface.md §4.6).
    (* purpose = "A drive [7:0]" *)   sn74ahct244 ad0 (.a(a_pre[7:0]),   .oe1_n(bus_oe_n), .oe2_n(bus_oe_n), .y(a[7:0]));
    (* purpose = "A drive [15:8]" *)  sn74ahct244 ad1 (.a(a_pre[15:8]),  .oe1_n(bus_oe_n), .oe2_n(bus_oe_n), .y(a[15:8]));
    (* purpose = "A drive [23:16]" *) sn74ahct244 ad2 (.a(a_pre[23:16]), .oe1_n(bus_oe_n), .oe2_n(bus_oe_n), .y(a[23:16]));

    // --- MDR + external bus port. MDR drives LEFT (low lane); write data = Z low. ---
    // (The MMU owns A[23:0] now, so memory_interface's own identity-A output is left unconnected.)
    (* purpose = "MDR + memory bus port" *)
    memory_interface mi (
        .clk(clk),
        .mem_op_n(mem_op_n), .z_dest_mdr_n(z_dest_n[7]), .left_src_mdr_n(left_src_n[10]),
        .bus_inhibit(bus_inhibit),
        .addr(addr_logical), .z_lo(z[7:0]),
        .mdr_q(mdr_q), .z_post(z), .left_lo(left_raw[7:0]),
        .a(), .d(d), .rd_n(mi_rd_n), .wr_n(mi_wr_n)
    );
    // /RD //WR south-edge drivers — tri-stated on a bus grant.
    (* purpose = "/RD //WR drive (tri-state on grant)" *)
    sn74ahct541 rwdrv (.a({6'b0, mi_wr_n, mi_rd_n}), .oe1_n(bus_oe_n), .oe2_n(1'b0), .y({rwz, wr_n, rd_n}));
    wire [5:0] rwz;     // the '541's unused high outputs

    // --- opcode register IR: latch the read byte on IR_LOAD, or from ir_drive (debug) --
    // The opcode being fetched is on Z[7:0] (the read post) DURING the fetch read, so a single
    // FETCH word `IR <- [PC]; PC++; dispatch` latches it and (via the LUT indexed on ir_d below)
    // dispatches on it in the same cycle.
    wire [7:0] ir, ir_inner, ir_d;
    (* purpose = "IR src: read byte vs hold [3:0]" *)
    sn74ahct157 iri0 (.a(z[3:0]), .b(ir[3:0]), .sel(ir_load_n[1]), .g_n(1'b0), .y(ir_inner[3:0]));
    (* purpose = "IR src: read byte vs hold [7:4]" *)
    sn74ahct157 iri1 (.a(z[7:4]), .b(ir[7:4]), .sel(ir_load_n[1]), .g_n(1'b0), .y(ir_inner[7:4]));
    (* purpose = "IR src: inject vs fetch [3:0]" *)
    sn74ahct157 iro0 (.a(ir_inner[3:0]), .b(ir_drive[3:0]), .sel(ir_inject), .g_n(1'b0), .y(ir_d[3:0]));
    (* purpose = "IR src: inject vs fetch [7:4]" *)
    sn74ahct157 iro1 (.a(ir_inner[7:4]), .b(ir_drive[7:4]), .sel(ir_inject), .g_n(1'b0), .y(ir_d[7:4]));
    (* purpose = "opcode register IR" *)
    sn74ahct574 ir_reg (.Q(ir), .D(ir_d), .CLK(clk), .OE_n(1'b0));
    assign ir_q = ir;

    // --- the remaining LEFT sources: CC, IR_IMM, MMU_ENTRY -----------------
    // CC (LEFT_SRC=13) and IR_IMM (LEFT_SRC=11) are 8-bit, so they drive only the LEFT low lane
    // (the LEFT_LANE steer zero-/sign-extends the high byte). IR_IMM is the IR byte as an inline
    // immediate. MMU_ENTRY (LEFT_SRC=12) is the 16-bit page-table entry latch (LDMMU/STMMU).
    (* purpose = "CC -> LEFT low lane" *)
    sn74ahct541 cclr (.a(cc_q), .oe1_n(left_src_n[13]), .oe2_n(1'b0), .y(left_raw[7:0]));
    (* purpose = "IR_IMM -> LEFT low lane" *)
    sn74ahct541 irlr (.a(ir), .oe1_n(left_src_n[11]), .oe2_n(1'b0), .y(left_raw[7:0]));
    (* purpose = "MMU_ENTRY latch + LEFT driver" *)
    mmu_entry u_mmu_entry (
        .clk(clk), .left_in(left_raw), .entry_rd(mmu_entry_rd),
        .load_n(mmu_pt_n[1]), .read_n(mmu_pt_n[2]), .drive_n(left_src_n[12]),
        .q(mmu_entry_q), .left_out(left_raw)
    );

    // --- ULOOP micro-loop counter: terminal -> cond[8] ---------------------
    // ULOOP_CTRL is the sequencer field cw_wcs[21:20]; the count loads from the Z low bits.
    wire uloop_zero;
    (* purpose = "ULOOP micro-loop counter" *)
    uloop u_uloop (.clk(clk), .reset_n(reg_reset_n), .uloop_ctrl(cw_wcs[21:20]),
                   .z_lo(z[4:0]), .uloop_zero(uloop_zero));

    // --- IRQ I-mask + RETURN_FETCH decode (for the trap encoder) -----------
    // irq_masked = irq & ~CC.I (R-CPU-6: a masked IRQ is never recognised, in hardware — the same
    // single source feeds cond[9] and the trap encoder). retfetch_active = USEQ_OP==RETURN_FETCH.
    // ---- fault detectors: PRIV_VIOLATION (priv opcode in user) + ILLEGAL_OPCODE (LUT VALID=0).
    // The opcode-LUT carries a privileged bit (lut_hi[4]) and a VALID bit (lut_hi[5]); both index
    // off the current IR (ir_d). These (combinational) drive cond[13]/[14] for the microcode to
    // branch on; wiring them as RETURN_FETCH/dispatch trap sources is the remaining refinement.
    wire [5:0] tiv;
    (* purpose = "~CC.I; ~USEQ_OP[1:0]; ~CC.M; illegal=~VALID" *)
    sn74ahct04 tinv (.a({1'b0, lut_hi[5], cc_q[7], cw_wcs[1], cw_wcs[0], cc_q[4]}), .y(tiv));
    wire nI = tiv[0], nU0 = tiv[1], nU1 = tiv[2], nM = tiv[3], illegal_op = tiv[4];
    wire [3:0] tand;
    (* purpose = "irq_masked; retfetch_active; priv_violation" *)
    sn74ahct08 tandg (.a({lut_hi[4], cw_wcs[2], nU0, irq}), .b({nM, tand[1], nU1, nI}), .y(tand));
    wire irq_masked = tand[0];           // irq & ~CC.I
    wire retfetch_active = tand[2];      // USEQ_OP==RETURN_FETCH(4) = u2 & ~u1 & ~u0
    wire priv_violation = tand[3];       // lut_priv & ~CC.M

    // --- trap-vector encoder: redirect RETURN_FETCH to a pending trap entry -
    // NMI is taken as a level here (the edge-latch is a documented refinement).
    wire [11:0] trap_entry;
    wire        trap_pending;
    (* purpose = "trap-vector priority encoder" *)
    trap_encoder u_trap (
        .nmi_pending(nmi), .irq_masked(irq_masked), .retfetch_active(retfetch_active),
        .trap_entry(trap_entry), .trap_pending(trap_pending)
    );

    // --- condition lines into the sequencer --------------------------------
    // cond[6:0] = cond_inject ? cond_drive[6:0] : CC-derived ; cond[7] = TRUE slot ;
    // cond[15:8] = cond_inject ? cond_drive[15:8] : the internal microconditions:
    //   [8]=ULOOP [9]=IRQ(masked) [10]=NMI [11]=WAIT_READY [12..14]=fault flags (unbuilt) [15]=spare.
    wire [15:0] cond_seq;
    wire [7:0]  internal_cond = {1'b0, illegal_op, priv_violation, 1'b0,
                                 wait_ready, nmi, irq_masked, uloop_zero};
    wire [3:0]  cci1_y;
    (* purpose = "cond mux CC vs inject [3:0]" *)
    sn74ahct157 cci0 (.a(cc_cond[3:0]), .b(cond_drive[3:0]), .sel(cond_inject), .g_n(1'b0), .y(cond_seq[3:0]));
    (* purpose = "cond mux CC vs inject [6:4]" *)
    sn74ahct157 cci1 (.a({1'b0, cc_cond[6:4]}), .b({1'b0, cond_drive[6:4]}), .sel(cond_inject), .g_n(1'b0), .y(cci1_y));
    assign cond_seq[6:4]  = cci1_y[2:0];
    assign cond_seq[7]    = cond_drive[7];      // TRUE slot (forced in the sequencer anyway)
    (* purpose = "internal cond mux [11:8]" *)
    sn74ahct157 cii0 (.a(internal_cond[3:0]), .b(cond_drive[11:8]),  .sel(cond_inject), .g_n(1'b0), .y(cond_seq[11:8]));
    (* purpose = "internal cond mux [15:12]" *)
    sn74ahct157 cii1 (.a(internal_cond[7:4]), .b(cond_drive[15:12]), .sel(cond_inject), .g_n(1'b0), .y(cond_seq[15:12]));

    // --- microsequencer ----------------------------------------------------
    wire [11:0] lut_data;
    (* purpose = "micro-sequencer (next uPC)" *)
    microsequencer useq (
        .clk(clk), .clr_n(run),
        .useq_op(cw_wcs[2:0]), .next_addr(cw_wcs[14:3]),
        .ucond_sel(cw_wcs[18:15]), .ucond_pol(cw_wcs[19]),
        .cond(cond_seq), .lut_data(lut_data),
        .trap_entry(trap_entry), .trap_pending(trap_pending), .upc(upc)
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
        .clk(clk), .loader_addr(loader_addr), .dispatch_page(cw_wcs[22]), .ir(ir_d), .loading(loading),
        .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .cs_n(cs_sel_n[12:11]), .lut_lo(lut_lo), .lut_hi(lut_hi)
    );

    assign cw       = cw_wcs;
    assign lut_data = {lut_hi[3:0], lut_lo};
    assign lut_out  = lut_data;
endmodule
`default_nettype wire
