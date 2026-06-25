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
//   CALL         µSR <- µPC+1 ; µPC <- NEXT_ADDR   (leaf micro-subroutine call, D-42)
//   RETURN       µPC <- µSR                        (return to the caller's next step)
//   RETURN_FETCH µPC <- 0                      (the fetch entry; trap-vector encoder TODO)
//   WAIT         µPC hold                      (a stretched bus cycle / single-step)
//
// DEFERRED (fall through to INC/count for now, harmlessly): the trap-vector priority encoder
// (RETURN_FETCH only vectors to 0) and the registered (pipelined) control-word output. The
// control word is read combinationally from the WCS, so the word at µPC drives this logic and
// the µPC clocks to the next value each cycle.
//
// Structure (the BOM):
//   3x cd74act161  -> the 12-bit µPC: synchronous LOAD# (load the next-address mux output)
//                     or count (+1) or hold; CLR# clears it to the fetch entry (0) in boot.
//   3x sn74f283    -> the µPC+1 adder feeding the µSR (the CALL return address).
//   3x cd74act161  -> the 12-bit µSR (depth-1, load-only on CALL); RETURN reads it.
//   1x sn74ahct04  -> call_active/return_active (+ the existing op-decode inverters).
//   1x sn74ahct32  -> the widened mux selects + the CALL/RETURN do_load terms.
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
    // ---- trap-vector encoder: redirect RETURN_FETCH to a pending trap's entry ----
    input  wire [11:0] trap_entry,
    input  wire        trap_pending,
    // ---- bus-grant stall: HIGH freezes the µPC (no count, no load) so a held bus grant
    //      stalls the core (interface.md §4.6, R-IF-4). Forces count_en LOW and LOAD# HIGH. ----
    input  wire        hold,
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
    wire   nhold  = inv_y[5];                  // ~hold (spare '04 inverter; HIGH when running)
    assign inv_a  = {hold, do_load, op_n[4], op_n[3], op_n[2], op_n[1]};
    (* purpose = "op decode + LOAD# + ~hold" *)
    sn74ahct04 inv (.a(inv_a), .y(inv_y));

    // BRANCH load term: branch_active & cond_taken  (one '08 gate). Gate 1 of the same '08 forms
    // the µPC count enable = (NOT WAIT) & (NOT hold): a held bus grant freezes the count.
    wire [3:0] and_y;
    (* purpose = "branch AND; count_en = ~WAIT & ~hold" *)
    sn74ahct08 brand (.a({2'b0, op_n[5], branch_active}), .b({2'b0, nhold, cond_taken}), .y(and_y));
    wire br_term  = and_y[0];
    wire count_en = and_y[1];                  // op_n[5] (NOT WAIT) AND ~hold

    // base_do_load = jump | br_term | dispatch | retfetch  (three gates of one '32; the package's
    // own gate-0/gate-1 outputs feed gate-2 — an ordinary on-board cascade, not a loop):
    //   y[0] = jump_active   | br_term
    //   y[1] = dispatch_active | retfetch_active
    //   y[2] = y[0] | y[1]   = base_do_load
    // Gate 3 of the same '32 forms LOAD#_eff = LOAD# | hold: a held bus grant forces LOAD# HIGH
    // (no load). load_n (=~do_load) depends on or_y[2] via seqor→inv, and or_y[3] feeds nothing
    // back into or_y[0..2] — a feed-forward extension of the on-board cascade, not a loop.
    wire [3:0] or_y;
    (* purpose = "do_load base OR tree; LOAD#|hold" *)
    sn74ahct32 lor (
        .a({load_n, or_y[0], dispatch_active, jump_active}),
        .b({hold,   or_y[1], retfetch_active, br_term}),
        .y(or_y));
    wire base_do_load = or_y[2];
    wire load_n_eff   = or_y[3];               // LOAD# forced HIGH while hold

    // CALL/RETURN active-high (op_n[6]/op_n[7] are the active-low CALL/RETURN strobes).
    wire [5:0] cr_inv;
    (* purpose = "call_active; return_active" *)
    sn74ahct04 crinv (.a({4'b0000, op_n[7], op_n[6]}), .y(cr_inv));
    wire call_active = cr_inv[0], return_active = cr_inv[1];

    // Widen the next-addr select so RETURN picks slot 11 (the µSR), and add the CALL/RETURN load
    // terms. sq[3] reads sq[2] — a feed-forward cascade within the package (the same idiom as
    // `lor`), not a true loop.
    //   sq[0] = dispatch | return = mux_sel_a    sq[2] = call | return = cr
    //   sq[1] = retfetch | return = mux_sel_b    sq[3] = base | cr     = do_load
    wire [3:0] sq;
    (* purpose = "mux selects; call|return; do_load" *)
    sn74ahct32 seqor (
        .a({base_do_load, call_active,  retfetch_active, dispatch_active}),
        .b({sq[2],        return_active, return_active,  return_active}),
        .y(sq));
    wire mux_sel_a = sq[0];
    wire mux_sel_b = sq[1];
    assign do_load = sq[3];

    // count enable (count_en) is computed in `brand` above: op_n[5] (NOT WAIT) AND ~hold, so the
    // µPC holds on WAIT or while the bus is granted away; LOAD#_eff dominates on a load op.

    // ---- µPC+1 adder (3x '283): the CALL return address (caller's next step) -----
    // The µPC '161 hides its internal +1 and on a CALL edge loads NEXT_ADDR, so the return point
    // cannot be captured from the counter — a dedicated adder on upc_q is required.
    wire [11:0] upc_plus1;
    wire [2:0]  addc;
    (* purpose = "uPC+1 [3:0]" *)
    sn74f283 ad0 (.A(upc_q[3:0]),   .B(4'b0000), .C0(1'b1),    .S(upc_plus1[3:0]),   .C4(addc[0]));
    (* purpose = "uPC+1 [7:4]" *)
    sn74f283 ad1 (.A(upc_q[7:4]),   .B(4'b0000), .C0(addc[0]), .S(upc_plus1[7:4]),   .C4(addc[1]));
    (* purpose = "uPC+1 [11:8]" *)
    sn74f283 ad2 (.A(upc_q[11:8]),  .B(4'b0000), .C0(addc[1]), .S(upc_plus1[11:8]),  .C4(addc[2]));

    // ---- µSR: depth-1 micro-subroutine return register; loads µPC+1 on CALL ------
    // Leaf-only (a called routine must not itself CALL — microcode discipline, not interlocked).
    wire [11:0] usr_q;
    wire [2:0]  usr_rco;
    (* purpose = "uSR [3:0]" *)
    cd74act161 sr0 (.clk(clk), .clr_n(clr_n), .load_n(op_n[6]), .enp(1'b0), .ent(1'b0),
                    .p(upc_plus1[3:0]),   .q(usr_q[3:0]),   .rco(usr_rco[0]));
    (* purpose = "uSR [7:4]" *)
    cd74act161 sr1 (.clk(clk), .clr_n(clr_n), .load_n(op_n[6]), .enp(1'b0), .ent(1'b0),
                    .p(upc_plus1[7:4]),   .q(usr_q[7:4]),   .rco(usr_rco[1]));
    (* purpose = "uSR [11:8]" *)
    cd74act161 sr2 (.clk(clk), .clr_n(clr_n), .load_n(op_n[6]), .enp(1'b0), .ent(1'b0),
                    .p(upc_plus1[11:8]),  .q(usr_q[11:8]),  .rco(usr_rco[2]));

    // ---- RETURN_FETCH target: a pending trap's entry, else the fetch entry 0 ----------------
    wire [11:0] fetch_or_trap;
    (* purpose = "trap_entry / fetch-0 [3:0]" *)
    sn74ahct157 ft0 (.a(4'b0), .b(trap_entry[3:0]),  .sel(trap_pending), .g_n(1'b0), .y(fetch_or_trap[3:0]));
    (* purpose = "trap_entry / fetch-0 [7:4]" *)
    sn74ahct157 ft1 (.a(4'b0), .b(trap_entry[7:4]),  .sel(trap_pending), .g_n(1'b0), .y(fetch_or_trap[7:4]));
    (* purpose = "trap_entry / fetch-0 [11:8]" *)
    sn74ahct157 ft2 (.a(4'b0), .b(trap_entry[11:8]), .sel(trap_pending), .g_n(1'b0), .y(fetch_or_trap[11:8]));

    // ---- next-address load mux: 6x '153 (4:1, 2 bits each) ------------------
    //   {sel_b, sel_a} = {retfetch|return, dispatch|return}:
    //     00 -> NEXT_ADDR (JUMP/CALL)   01 -> lut_data (DISPATCH)
    //     10 -> fetch_or_trap (RETURN_FETCH: 0, or a pending trap)   11 -> µSR (RETURN)
    wire [11:0] p;
    genvar i;
    generate for (i = 0; i < 6; i = i + 1) begin : nmux
        sn74act153 m (
            .a(mux_sel_a), .b(mux_sel_b),
            .g1_n(1'b0), .c1({usr_q[2*i],   fetch_or_trap[2*i],   lut_data[2*i],   next_addr[2*i]}),   .y1(p[2*i]),
            .g2_n(1'b0), .c2({usr_q[2*i+1], fetch_or_trap[2*i+1], lut_data[2*i+1], next_addr[2*i+1]}), .y2(p[2*i+1])
        );
    end endgenerate

    // ---- µPC: 3x '161 — load p / count(+1) / hold; CLR# = clr_n -------------
    wire [11:0] upc_q;
    wire [2:0]  upc_rco;
    (* purpose = "uPC [3:0]" *)
    cd74act161 u0 (.clk(clk), .clr_n(clr_n), .load_n(load_n_eff), .enp(count_en), .ent(count_en),
                   .p(p[3:0]),   .q(upc_q[3:0]),  .rco(upc_rco[0]));
    (* purpose = "uPC [7:4]" *)
    cd74act161 u1 (.clk(clk), .clr_n(clr_n), .load_n(load_n_eff), .enp(count_en), .ent(upc_rco[0]),
                   .p(p[7:4]),   .q(upc_q[7:4]),  .rco(upc_rco[1]));
    (* purpose = "uPC [11:8]" *)
    cd74act161 u2 (.clk(clk), .clr_n(clr_n), .load_n(load_n_eff), .enp(count_en), .ent(upc_rco[1]),
                   .p(p[11:8]),  .q(upc_q[11:8]), .rco(upc_rco[2]));
    assign upc = upc_q;
endmodule
`default_nettype wire
