// control_word_decoder — expands the 64-bit datapath section of the control word into
// the one-hot strobe lines the datapath consumes. Structural netlist of real chips
// (R-SIM-1, R-SIM-5; microcode.md §3.2).
//
// The control word is horizontal: most datapath fields are BINARY-encoded (one decoder
// each) and a few are literal/one-hot (pass straight through). This block is that bank of
// decoders. It takes only the datapath section (no field is shared with the sequencer
// section — microcode.md §3.1), in datapath-local bit numbering (local bit = full-word bit
// − 24, the datapath base): IR_LOAD at local 0, ... SPARE at local 63:58.
//
// Encoding: every binary field's value n drives the n-th output LOW (the '138/'139
// active-low convention), so each `*_n` bundle is a one-hot, active-low strobe set.
//
// Structure (the BOM):
//   8x sn74ahct139  -> the fifteen 2-bit fields (two 2->4 halves per package; one spare).
//   2x sn74ahct138  -> the two 3-bit fields (RIGHT_SRC, ALU_SHIFT), one 3->8 each.
//   6x sn74ahct138  -> the three 4-bit fields (LEFT_SRC, ALU_OP, Z_DEST) as 4->16 pairs:
//                      low 3 bits to A/B/C of both, bit 3 picks the half via complementary
//                      enables (no '154, no inverter) — the same trick as uc_loader.
//   (literal/mask fields ALU_CIN, ALU_WIDTH, FLAG_WE, Z_ACCUM, SP_BANK, TAS_LOCK are
//    already one-hot/direct and pass through as wires; SPARE is unused headroom.)
//
// SCAFFOLD: the datapath that consumes these strobes does not exist yet (hardware.md §2 is
// tentative), so the outputs drive nothing — they are observation/debug taps (R-DBG-5)
// until the registers/ALU/buses land. Building the decode now gives that datapath its
// control interface as real, verified chips.
`timescale 1ns/1ps
`default_nettype none
module control_word_decoder (
    input  wire [63:0] cw_dp,        // the datapath section (full-word bits [87:24])

    // --- decoded one-hot strobes (active LOW) -------------------------------
    output wire [3:0]  ir_load_n,    // IR_LOAD       (2->4)
    output wire [15:0] left_src_n,   // LEFT_SRC      (4->16)
    output wire [3:0]  left_lane_n,  // LEFT_LANE     (2->4)
    output wire [7:0]  right_src_n,  // RIGHT_SRC     (3->8)
    output wire [15:0] alu_op_n,     // ALU_OP        (4->16)
    output wire [7:0]  alu_shift_n,  // ALU_SHIFT     (3->8)
    output wire [3:0]  v_src_n,      // V_SRC         (2->4)
    output wire [3:0]  c_src_n,      // C_SRC         (2->4)
    output wire [3:0]  cc_write_n,   // CC_WRITE_SRC  (2->4)
    output wire [3:0]  cc_mi_n,      // CC_MI_LOAD    (2->4)
    output wire [15:0] z_dest_n,     // Z_DEST        (4->16)
    output wire [3:0]  z_lane_n,     // Z_LANE        (2->4)
    output wire [3:0]  pc_ctrl_n,    // PC_CTRL       (2->4)
    output wire [3:0]  mar_ctrl_n,   // MAR_CTRL      (2->4)
    output wire [3:0]  x_ctrl_n,     // X_CTRL        (2->4)
    output wire [3:0]  y_ctrl_n,     // Y_CTRL        (2->4)
    output wire [3:0]  mem_op_n,     // MEM_OP        (2->4)
    output wire [3:0]  mmu_addr_n,   // MMU_ADDR_SRC  (2->4)
    output wire [3:0]  mmu_map_n,    // MMU_MAP_SEL   (2->4)
    output wire [3:0]  mmu_pt_n,     // MMU_PT_OP     (2->4)

    // --- pass-through (literal/mask fields, already one-hot/direct) ---------
    output wire        alu_cin,      // ALU_CIN
    output wire        alu_width,    // ALU_WIDTH
    output wire [4:0]  flag_we,      // FLAG_WE (per-flag one-hot write-enables)
    output wire        z_accum,      // Z_ACCUM
    output wire        sp_bank,      // SP_BANK
    output wire        tas_lock      // TAS_LOCK
);
    // ---- field extraction (datapath-local bit ranges; pure rewiring) -------
    wire [1:0] ir_load   = cw_dp[1:0];
    wire [3:0] left_src  = cw_dp[5:2];
    wire [1:0] left_lane = cw_dp[7:6];
    wire [2:0] right_src = cw_dp[10:8];
    wire [3:0] alu_op    = cw_dp[14:11];
    wire [2:0] alu_shift = cw_dp[17:15];
    wire [1:0] v_src     = cw_dp[26:25];
    wire [1:0] c_src     = cw_dp[28:27];
    wire [1:0] cc_write  = cw_dp[31:30];
    wire [1:0] cc_mi     = cw_dp[33:32];
    wire [3:0] z_dest    = cw_dp[37:34];
    wire [1:0] z_lane    = cw_dp[39:38];
    wire [1:0] pc_ctrl   = cw_dp[41:40];
    wire [1:0] mar_ctrl  = cw_dp[43:42];
    wire [1:0] x_ctrl    = cw_dp[45:44];
    wire [1:0] y_ctrl    = cw_dp[47:46];
    wire [1:0] mem_op    = cw_dp[49:48];
    wire [1:0] mmu_addr  = cw_dp[51:50];
    wire [1:0] mmu_map   = cw_dp[53:52];
    wire [1:0] mmu_pt    = cw_dp[55:54];

    // ---- 2-bit fields: 15 halves of 8x '139 (2->4), always enabled ---------
    sn74ahct139 d0 (.g1_n(1'b0), .a1(ir_load[0]),  .b1(ir_load[1]),  .y1(ir_load_n),
                    .g2_n(1'b0), .a2(left_lane[0]), .b2(left_lane[1]), .y2(left_lane_n));
    sn74ahct139 d1 (.g1_n(1'b0), .a1(v_src[0]),    .b1(v_src[1]),    .y1(v_src_n),
                    .g2_n(1'b0), .a2(c_src[0]),     .b2(c_src[1]),    .y2(c_src_n));
    sn74ahct139 d2 (.g1_n(1'b0), .a1(cc_write[0]), .b1(cc_write[1]), .y1(cc_write_n),
                    .g2_n(1'b0), .a2(cc_mi[0]),     .b2(cc_mi[1]),    .y2(cc_mi_n));
    sn74ahct139 d3 (.g1_n(1'b0), .a1(z_lane[0]),   .b1(z_lane[1]),   .y1(z_lane_n),
                    .g2_n(1'b0), .a2(pc_ctrl[0]),   .b2(pc_ctrl[1]),  .y2(pc_ctrl_n));
    sn74ahct139 d4 (.g1_n(1'b0), .a1(mar_ctrl[0]), .b1(mar_ctrl[1]), .y1(mar_ctrl_n),
                    .g2_n(1'b0), .a2(x_ctrl[0]),    .b2(x_ctrl[1]),   .y2(x_ctrl_n));
    sn74ahct139 d5 (.g1_n(1'b0), .a1(y_ctrl[0]),   .b1(y_ctrl[1]),   .y1(y_ctrl_n),
                    .g2_n(1'b0), .a2(mem_op[0]),    .b2(mem_op[1]),   .y2(mem_op_n));
    sn74ahct139 d6 (.g1_n(1'b0), .a1(mmu_addr[0]), .b1(mmu_addr[1]), .y1(mmu_addr_n),
                    .g2_n(1'b0), .a2(mmu_map[0]),   .b2(mmu_map[1]),  .y2(mmu_map_n));
    sn74ahct139 d7 (.g1_n(1'b0), .a1(mmu_pt[0]),   .b1(mmu_pt[1]),   .y1(mmu_pt_n),
                    .g2_n(1'b1), .a2(1'b0),         .b2(1'b0),        .y2());   // half spare

    // ---- 3-bit fields: one '138 (3->8) each, always enabled ----------------
    sn74ahct138 r_src (.a(right_src[0]), .b(right_src[1]), .c(right_src[2]),
                       .g1(1'b1), .g2a_n(1'b0), .g2b_n(1'b0), .y(right_src_n));
    sn74ahct138 a_sh  (.a(alu_shift[0]), .b(alu_shift[1]), .c(alu_shift[2]),
                       .g1(1'b1), .g2a_n(1'b0), .g2b_n(1'b0), .y(alu_shift_n));

    // ---- 4-bit fields: 4->16 from two '138 (bit 3 picks the half) ----------
    sn74ahct138 ls_lo (.a(left_src[0]), .b(left_src[1]), .c(left_src[2]),
                       .g1(1'b1), .g2a_n(left_src[3]), .g2b_n(1'b0), .y(left_src_n[7:0]));
    sn74ahct138 ls_hi (.a(left_src[0]), .b(left_src[1]), .c(left_src[2]),
                       .g1(left_src[3]), .g2a_n(1'b0), .g2b_n(1'b0), .y(left_src_n[15:8]));
    sn74ahct138 op_lo (.a(alu_op[0]), .b(alu_op[1]), .c(alu_op[2]),
                       .g1(1'b1), .g2a_n(alu_op[3]), .g2b_n(1'b0), .y(alu_op_n[7:0]));
    sn74ahct138 op_hi (.a(alu_op[0]), .b(alu_op[1]), .c(alu_op[2]),
                       .g1(alu_op[3]), .g2a_n(1'b0), .g2b_n(1'b0), .y(alu_op_n[15:8]));
    sn74ahct138 zd_lo (.a(z_dest[0]), .b(z_dest[1]), .c(z_dest[2]),
                       .g1(1'b1), .g2a_n(z_dest[3]), .g2b_n(1'b0), .y(z_dest_n[7:0]));
    sn74ahct138 zd_hi (.a(z_dest[0]), .b(z_dest[1]), .c(z_dest[2]),
                       .g1(z_dest[3]), .g2a_n(1'b0), .g2b_n(1'b0), .y(z_dest_n[15:8]));

    // ---- literal / mask fields: pass through (pure rewiring) ---------------
    assign alu_cin   = cw_dp[18];
    assign alu_width = cw_dp[19];
    assign flag_we   = cw_dp[24:20];
    assign z_accum   = cw_dp[29];
    assign sp_bank   = cw_dp[56];
    assign tas_lock  = cw_dp[57];
endmodule
`default_nettype wire
