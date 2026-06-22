// microsequencer — the micro-program counter (µPC) and its next-address logic.
// Structural netlist of real chips (R-SIM-1, R-SIM-5; microcode.md §2).
//
// The sequencer section of the control word fully determines the next µPC (no datapath
// field touches it). This block implements the fetch/branch core of USEQ_OP:
//
//   INC          µPC + 1                      (the default — a free counter increment)
//   JUMP         µPC <- NEXT_ADDR             (unconditional)
//   BRANCH       µPC <- NEXT_ADDR if (cond ^ UCOND_POL) else µPC + 1
//   DISPATCH_IR  µPC <- lut_data              (the opcode-LUT start address, {PAGE,IR})
//   RETURN_FETCH µPC <- 0                      (the fetch entry; trap-vector encoder TODO)
//   WAIT         µPC hold                      (a stretched bus cycle / single-step)
//
// DEFERRED (fall through to INC/count for now, harmlessly): CALL / RETURN + the µSR return
// register, the ULOOP loop counter, the trap-vector priority encoder, and the registered
// (pipelined) control-word output. The control word is read combinationally from the WCS,
// so the word at µPC drives this logic and the µPC clocks to the next value each cycle.
//
// Structure (the BOM):
//   3x cd74act161  -> the 12-bit µPC: synchronous LOAD# (load the next-address mux output)
//                     or count (+1) or hold; CLR# clears it to the fetch entry (0) in boot.
//   1x sn74ahct138 -> USEQ_OP one-hot (active-low op lines).
//   1x sn74ahct04  -> invert the op lines we act on (branch/jump/dispatch/retfetch) and
//                     form LOAD# = ~do_load.
//   1x sn74ahct08  -> the conditional-branch AND: branch_active & cond_taken.
//   1x sn74ahct32  -> OR the load terms into do_load.
//   6x sn74act153  -> the 12-bit next-address load mux (4:1: NEXT_ADDR / lut_data / 0 / 0),
//                     selected by {retfetch, dispatch} from the USEQ_OP decode.
//   2x cd74act151  -> the 16:1 condition mux (8 low + 8 high), selected by UCOND_SEL.
//   1x sn74ahct157 -> the low/high condition-group 2:1 merge (UCOND_SEL[3]).
//   1x sn74ahct86  -> condition polarity: cond_taken = cond ^ UCOND_POL.
//
// SCAFFOLD: the condition lines (CC flags + microconditions) do not exist yet (no datapath
// — hardware.md §2), so they arrive as the `cond` input (driven externally/by the bench);
// index 7 (TRUE) is forced HIGH internally, so an all-zero `cond` still gives a working
// always-true / always-false branch via UCOND_POL.
`timescale 1ns/1ps
`default_nettype none
module microsequencer (
    input  wire        clk,
    input  wire        clr_n,        // async clear to the fetch entry 0 (= run): LOW in boot
    // ---- sequencer-section control-word fields ----
    input  wire [2:0]  useq_op,      // INC/BRANCH/JUMP/DISPATCH_IR/RETURN_FETCH/WAIT/CALL/RETURN
    input  wire [11:0] next_addr,    // branch / jump target
    input  wire [3:0]  ucond_sel,    // 1-of-16 condition select
    input  wire        ucond_pol,    // condition polarity (XOR)
    // ---- condition lines (signals, not control-word fields); index 7 forced TRUE ----
    input  wire [15:0] cond,
    // ---- opcode-LUT dispatch target ({PAGE, IR} lookup, from opcode_lut) ----
    input  wire [11:0] lut_data,
    output wire [11:0] upc
);
    // ---- USEQ_OP one-hot (active LOW): op_n[k] low <=> USEQ_OP == k ----------
    wire [7:0] op_n;
    (* purpose = "USEQ_OP decode (1-of-8)" *)
    sn74ahct138 useq (.a(useq_op[0]), .b(useq_op[1]), .c(useq_op[2]),
                      .g1(1'b1), .g2a_n(1'b0), .g2b_n(1'b0), .y(op_n));
    // op_n[0]=INC [1]=BRANCH [2]=JUMP [3]=DISPATCH_IR [4]=RETURN_FETCH [5]=WAIT [6]=CALL [7]=RETURN

    // ---- condition mux: 16:1 (2x '151 + a '157 merge) then XOR polarity ------
    wire cond_lo, cond_hi, cond_raw, cond_taken;
    (* purpose = "cond mux 0..7" *)
    cd74act151 cmux_lo (.a(ucond_sel[0]), .b(ucond_sel[1]), .c(ucond_sel[2]), .g_n(1'b0),
                        .d({1'b1, cond[6:0]}), .y(cond_lo), .w());      // d[7] = TRUE
    (* purpose = "cond mux 8..15" *)
    cd74act151 cmux_hi (.a(ucond_sel[0]), .b(ucond_sel[1]), .c(ucond_sel[2]), .g_n(1'b0),
                        .d(cond[15:8]), .y(cond_hi), .w());
    wire [3:0] merge_y;
    (* purpose = "cond lo/hi merge" *)
    sn74ahct157 cmerge (.a({3'b0, cond_lo}), .b({3'b0, cond_hi}), .sel(ucond_sel[3]),
                        .g_n(1'b0), .y(merge_y));
    assign cond_raw = merge_y[0];
    wire [3:0] xor_y;
    (* purpose = "cond polarity XOR" *)
    sn74ahct86 cpol (.a({3'b0, cond_raw}), .b({3'b0, ucond_pol}), .y(xor_y));
    assign cond_taken = xor_y[0];

    // ---- USEQ_OP decode -> control lines (all real gates) -------------------
    // active-high op signals (and LOAD#) from one '04; spare inverter unused.
    wire [5:0] inv_a, inv_y;
    wire branch_active   = inv_y[0];
    wire jump_active     = inv_y[1];
    wire dispatch_active = inv_y[2];   // also next-addr mux select A (pick lut_data)
    wire retfetch_active = inv_y[3];   // also next-addr mux select B (pick fetch entry 0)
    wire do_load, load_n;
    assign load_n = inv_y[4];
    assign inv_a  = {1'b0, do_load, op_n[4], op_n[3], op_n[2], op_n[1]};
    (* purpose = "op decode + LOAD#" *)
    sn74ahct04 inv (.a(inv_a), .y(inv_y));

    // BRANCH load term: branch_active & cond_taken  (one '08 gate)
    wire [3:0] and_y;
    (* purpose = "branch AND" *)
    sn74ahct08 brand (.a({3'b0, branch_active}), .b({3'b0, cond_taken}), .y(and_y));
    wire br_term = and_y[0];

    // do_load = jump | br_term | dispatch | retfetch  (three gates of one '32; the package's
    // own gate-0/gate-1 outputs feed gate-2 — an ordinary on-board cascade, not a loop):
    //   y[0] = jump_active   | br_term
    //   y[1] = dispatch_active | retfetch_active
    //   y[2] = y[0] | y[1]   = do_load
    wire [3:0] or_y;
    (* purpose = "do_load OR tree" *)
    sn74ahct32 lor (
        .a({1'b0, or_y[0], dispatch_active, jump_active}),
        .b({1'b0, or_y[1], retfetch_active, br_term}),
        .y(or_y));
    assign do_load = or_y[2];

    // count enable = NOT WAIT: op_n[5] is LOW only on WAIT, so use it directly as the
    // active-high count enable (hold on WAIT; LOAD# dominates on load ops).
    wire count_en = op_n[5];

    // ---- next-address load mux: 6x '153 (4:1, 2 bits each) ------------------
    //   {sel_b, sel_a} = {retfetch_active, dispatch_active}:
    //     00 -> NEXT_ADDR   01 -> lut_data   10 -> 0 (fetch entry)   11 -> 0
    wire [11:0] p;
    genvar i;
    generate for (i = 0; i < 6; i = i + 1) begin : nmux
        sn74act153 m (
            .a(dispatch_active), .b(retfetch_active),
            .g1_n(1'b0), .c1({2'b00, lut_data[2*i],   next_addr[2*i]}),   .y1(p[2*i]),
            .g2_n(1'b0), .c2({2'b00, lut_data[2*i+1], next_addr[2*i+1]}), .y2(p[2*i+1])
        );
    end endgenerate

    // ---- µPC: 3x '161 — load p / count(+1) / hold; CLR# = clr_n -------------
    wire [11:0] upc_q;
    wire [2:0]  upc_rco;
    (* purpose = "uPC [3:0]" *)
    cd74act161 u0 (.clk(clk), .clr_n(clr_n), .load_n(load_n), .enp(count_en), .ent(count_en),
                   .p(p[3:0]),   .q(upc_q[3:0]),  .rco(upc_rco[0]));
    (* purpose = "uPC [7:4]" *)
    cd74act161 u1 (.clk(clk), .clr_n(clr_n), .load_n(load_n), .enp(count_en), .ent(upc_rco[0]),
                   .p(p[7:4]),   .q(upc_q[7:4]),  .rco(upc_rco[1]));
    (* purpose = "uPC [11:8]" *)
    cd74act161 u2 (.clk(clk), .clr_n(clr_n), .load_n(load_n), .enp(count_en), .ent(upc_rco[1]),
                   .p(p[11:8]),  .q(upc_q[11:8]), .rco(upc_rco[2]));
    assign upc = upc_q;
endmodule
`default_nettype wire
