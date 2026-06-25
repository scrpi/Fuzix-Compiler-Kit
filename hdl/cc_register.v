// cc_register — the 8-bit condition-code register CC (M – H I N Z V C) and its write logic.
// Structural netlist of real chips (R-SIM-1, R-SIM-5; isa.md §8.4/§8.5/§8.7; R-CPU-1/-4/-6).
//
// CC bit layout (isa.md §8.4): cc_q[7]=M(supervisor) [6]=reserved [5]=H [4]=I(IRQ mask)
// [3]=N [2]=Z [1]=V [0]=C. Held in a '574; each bit recirculates (hold) unless its write
// path latches a new value this cycle.
//
// Write paths:
//   * The LOW flags H/N/Z/V/C take their value from CC_WRITE_SRC and load per FLAG_WE:
//       ALU_FLAGS  -> the ALU's computed flag for that bit, loaded only if FLAG_WE selects it.
//                     V and C are first overridden by V_SRC/C_SRC (FROM_ALU/FORCE_0/FORCE_1);
//                     Z is AND'd with the prior Z when Z_ACCUM (16-bit zero over two byte
//                     cycles). H/N pass through.
//       WHOLE_Z    -> the Z-bus low byte (RTI / PULS CC), all low flags loaded.
//       AND_MASK / OR_MASK -> CC AND/OR the Z mask (ANDCC / ORCC), all low flags loaded.
//   * The MODE bits M/I are written when EITHER a whole/masked CC write occurs (CC_WRITE_SRC=
//     WHOLE_Z/AND/OR — RTI/PULS CC restore them, ANDCC/ORCC mask them, all from src8[7]/[4]),
//     OR CC_MI_LOAD drives them directly: SET_ON_ENTRY forces both to 1 (trap entry); SET_I/
//     CLR_I set/clear I alone with M held (the privileged SEI/CLI). A privilege interlock gates
//     every M/I write: it happens only in supervisor mode (CC.M=1) OR on SET_ON_ENTRY (the trap
//     entry that itself enters supervisor) — so user code cannot clear its own IRQ mask or leave
//     user mode; a user-mode whole/mask write still loads H/N/Z/V/C but holds M/I (R-CPU-4/-6,
//     isa.md §8.7).
//   * Reset (R-CPU-7, D-15): CC comes up 0x90 — supervisor (M=1), IRQ masked (I=1), flags 0.
//
// Every chained gate crosses package boundaries (a cell's `assign y = a OP b` is one atomic
// vector op, so a package output must not feed that same package's input).
`timescale 1ns/1ps
`default_nettype none
module cc_register (
    input  wire        clk,
    input  wire        reset_n,        // active-low: CC <- 0x90 (supervisor, IRQ masked)
    // ---- ALU flags ----
    input  wire        flag_n, flag_z, flag_v, flag_c, flag_h,
    // ---- decoded control ----
    input  wire [4:0]  flag_we,        // mask: [0]=WE_H [1]=WE_N [2]=WE_Z [3]=WE_V [4]=WE_C
    input  wire [3:0]  v_src_n,        // V_SRC one-hot, active LOW (FROM_ALU=0,FORCE_0=1,FORCE_1=2)
    input  wire [3:0]  c_src_n,        // C_SRC one-hot, active LOW
    input  wire        z_accum,        // Z_ACCUM: AND new Z with prior Z
    input  wire [3:0]  cc_write_n,     // CC_WRITE_SRC one-hot (ALU_FLAGS=0,WHOLE_Z=1,AND=2,OR=3)
    input  wire [3:0]  cc_mi_n,        // CC_MI_LOAD one-hot (HOLD=0,SET_ON_ENTRY=1,SET_I=2,CLR_I=3)
    input  wire [7:0]  z_lo,           // Z-bus low byte (WHOLE_Z / mask source)
    // ---- outputs ----
    output wire [7:0]  cc_q,           // the CC register
    output wire        cc_m            // CC.M (supervisor) — to SP-bank / MMU / sequencer
);
    assign cc_m = cc_q[7];

    // ---- inverters (senses) --------------------------------------------------------
    wire [5:0] inv_a;
    (* purpose = "senses: zacc/Vsrc/Csrc/ALUflags" *)
    sn74ahct04 ia (.a({cc_write_n[0], c_src_n[2], c_src_n[0], v_src_n[2], v_src_n[0], z_accum}), .y(inv_a));
    wire nz_accum = inv_a[0], from_alu_v = inv_a[1], force1_v = inv_a[2];
    wire from_alu_c = inv_a[3], force1_c = inv_a[4], alu_flags_mode = inv_a[5];

    // ---- ALU-flag candidates after V_SRC/C_SRC/Z_ACCUM -----------------------------
    wire [3:0] zr;
    (* purpose = "Z-accum OR (cc.Z | ~Zacc)" *)
    sn74ahct32 zor (.a({3'b0, cc_q[2]}), .b({3'b0, nz_accum}), .y(zr));
    wire [3:0] aa;
    (* purpose = "af_z; t_v; t_c" *)
    sn74ahct08 afa (.a({1'b0, from_alu_c, from_alu_v, flag_z}), .b({1'b0, flag_c, flag_v, zr[0]}), .y(aa));
    wire af_z = aa[0], t_v = aa[1], t_c = aa[2];
    wire [3:0] ao;
    (* purpose = "af_v; af_c" *)
    sn74ahct32 afo (.a({2'b0, t_c, t_v}), .b({2'b0, force1_c, force1_v}), .y(ao));
    wire af_v = ao[0], af_c = ao[1];
    // ALU_FLAGS source byte: only H/N/Z/V/C positions matter (M/I/bit6 handled elsewhere).
    wire [7:0] af8 = {2'b00, flag_h, 1'b0, flag_n, af_z, af_v, af_c};

    // ---- AND/OR mask bytes (CC op Z) -----------------------------------------------
    wire [7:0] and8, or8;
    (* purpose = "CC&Z [3:0]" *)  sn74ahct08 ma0 (.a(cc_q[3:0]), .b(z_lo[3:0]), .y(and8[3:0]));
    (* purpose = "CC&Z [7:4]" *)  sn74ahct08 ma1 (.a(cc_q[7:4]), .b(z_lo[7:4]), .y(and8[7:4]));
    (* purpose = "CC|Z [3:0]" *)  sn74ahct32 mo0 (.a(cc_q[3:0]), .b(z_lo[3:0]), .y(or8[3:0]));
    (* purpose = "CC|Z [7:4]" *)  sn74ahct32 mo1 (.a(cc_q[7:4]), .b(z_lo[7:4]), .y(or8[7:4]));

    // ---- low-flag source byte: CC_WRITE_SRC tri-state mux (one-hot, active-low) -----
    wire [7:0] src8;
    (* purpose = "src<-ALU flags" *)  sn74ahct541 dsa (.a(af8),  .oe1_n(cc_write_n[0]), .oe2_n(1'b0), .y(src8));
    (* purpose = "src<-Z (whole)" *)  sn74ahct541 dsz (.a(z_lo), .oe1_n(cc_write_n[1]), .oe2_n(1'b0), .y(src8));
    (* purpose = "src<-CC&Z" *)       sn74ahct541 dsn (.a(and8), .oe1_n(cc_write_n[2]), .oe2_n(1'b0), .y(src8));
    (* purpose = "src<-CC|Z" *)       sn74ahct541 dso (.a(or8),  .oe1_n(cc_write_n[3]), .oe2_n(1'b0), .y(src8));

    // ---- whole_or_mask = any of WHOLE_Z/AND/OR active (across packages) -------------
    wire [3:0] wm1, wm2;
    (* purpose = "wm_a = WHOLE_Z,AND_MASK deselected" *)
    sn74ahct08 wma1 (.a({3'b0, cc_write_n[1]}), .b({3'b0, cc_write_n[2]}), .y(wm1));
    wire wm_a = wm1[0];
    (* purpose = "wm_b = + OR_MASK deselected" *)
    sn74ahct08 wma2 (.a({3'b0, wm_a}), .b({3'b0, cc_write_n[3]}), .y(wm2));
    wire wm_b = wm2[0];                               // none of WHOLE_Z/AND/OR selected
    wire [5:0] inv_b;
    (* purpose = "whole_or_mask; set_on_entry; SET_I/CLR_I senses" *)
    sn74ahct04 ib (.a({2'b0, cc_mi_n[3], cc_mi_n[2], cc_mi_n[1], wm_b}), .y(inv_b));
    wire whole_or_mask = inv_b[0], set_on_entry = inv_b[1];
    wire set_i_sel = inv_b[2], clr_i_sel = inv_b[3];  // CC_MI_LOAD == SET_I / CLR_I

    // ---- M/I write control: privilege, explicit-I, per-bit load enables ------------
    // mi_write = (whole/masked CC write) | SET_ON_ENTRY ; explicit = SET_I | CLR_I (SEI/CLI, I
    // only). ld_m loads on mi_write; ld_i additionally on explicit — both gated by mi_priv.
    wire [3:0] mor;
    (* purpose = "explicit = SET_I|CLR_I; mi_write = whole|entry" *)
    sn74ahct32 mor1 (.a({2'b0, whole_or_mask, set_i_sel}), .b({2'b0, set_on_entry, clr_i_sel}), .y(mor));
    wire explicit = mor[0], mi_write = mor[1];
    wire [3:0] mip;
    (* purpose = "mi_priv = M|entry; ld_i_pre = mi_write|explicit" *)
    sn74ahct32 mip1 (.a({2'b0, mi_write, cc_q[7]}), .b({2'b0, explicit, set_on_entry}), .y(mip));
    wire mi_priv = mip[0], ld_i_pre = mip[1];
    wire [3:0] mld;
    (* purpose = "ld_m = priv&mi_write; ld_i = priv&ld_i_pre" *)
    sn74ahct08 mld1 (.a({2'b0, mi_priv, mi_priv}), .b({2'b0, ld_i_pre, mi_write}), .y(mld));
    wire ld_m = mld[0], ld_i = mld[1];

    // ---- M/I value sources ---------------------------------------------------------
    // M src = SET_ON_ENTRY | src8[7]  (forced 1 on entry, else the whole/masked byte's M bit).
    // I src = explicit ? i_val : (SET_ON_ENTRY | src8[4]) ; i_val = set_i_sel (SET_I->1, CLR_I->0).
    wire [3:0] msrc;
    (* purpose = "src_m; src_i_base (whole/entry)" *)
    sn74ahct32 msr1 (.a({2'b0, set_on_entry, set_on_entry}), .b({2'b0, src8[4], src8[7]}), .y(msrc));
    wire src_m = msrc[0], src_i_base = msrc[1];
    wire [3:0] isrc;
    (* purpose = "src_i = explicit ? i_val : src_i_base" *)
    sn74ahct157 isr (.a({3'b0, src_i_base}), .b({3'b0, set_i_sel}), .sel(explicit), .g_n(1'b0), .y(isrc));
    wire src_i = isrc[0];

    // ---- per-low-flag load enable: (ALU_FLAGS & FLAG_WE) | whole_or_mask -----------
    wire [3:0] tlo;
    (* purpose = "ALU_FLAGS&FLAG_WE C/V/Z/N" *)
    sn74ahct08 wlo (.a({alu_flags_mode, alu_flags_mode, alu_flags_mode, alu_flags_mode}),
                    .b({flag_we[1], flag_we[2], flag_we[3], flag_we[4]}), .y(tlo));
    // tlo[0]=C(WE_C=flag_we[4]) tlo[1]=V(WE_V=3) tlo[2]=Z(WE_Z=2) tlo[3]=N(WE_N=1)
    wire [3:0] th;
    (* purpose = "ALU_FLAGS&WE_H" *)
    sn74ahct08 wh (.a({3'b0, alu_flags_mode}), .b({3'b0, flag_we[0]}), .y(th));
    wire t_h = th[0];
    wire [3:0] ldl, ldl2;
    (* purpose = "ld C/V/Z/N = t | whole_or_mask" *)
    sn74ahct32 olo (.a(tlo), .b({4{whole_or_mask}}), .y(ldl));
    wire ld_c = ldl[0], ld_v = ldl[1], ld_z = ldl[2], ld_n = ldl[3];
    (* purpose = "ld H = t_h | whole_or_mask" *)
    sn74ahct32 oh (.a({3'b0, t_h}), .b({3'b0, whole_or_mask}), .y(ldl2));
    wire ld_h = ldl2[0];

    // ---- per-bit load-or-hold mux (AND-OR), 7 controlled bits ----------------------
    // ld_term = src & ld ; hold_term = cc_q & ~ld ; cc_dn = ld_term | hold_term. M and I now
    // take SEPARATE load enables (ld_m / ld_i) so SEI/CLI touch I alone.
    wire [5:0] nld;     // ~ld for C,V,Z,N,H
    (* purpose = "~ld C/V/Z/N/H" *)
    sn74ahct04 inl (.a({1'b0, ld_h, ld_n, ld_z, ld_v, ld_c}), .y(nld));
    wire nld_c=nld[0], nld_v=nld[1], nld_z=nld[2], nld_n=nld[3], nld_h=nld[4];
    wire [5:0] nlm;     // ~ld for M, I
    (* purpose = "~ld_m; ~ld_i" *)
    sn74ahct04 inmi (.a({4'b0, ld_i, ld_m}), .y(nlm));
    wire nld_m = nlm[0], nld_i = nlm[1];

    wire [3:0] lt0, lt1;        // ld_term: C,V,Z,N | H,M,I
    (* purpose = "ld_term C/V/Z/N" *)
    sn74ahct08 la0 (.a({src8[3], src8[2], src8[1], src8[0]}), .b({ld_n, ld_z, ld_v, ld_c}), .y(lt0));
    (* purpose = "ld_term H/M/I" *)
    sn74ahct08 la1 (.a({1'b0, src_i, src_m, src8[5]}), .b({1'b0, ld_i, ld_m, ld_h}), .y(lt1));
    wire [3:0] ht0, ht1;        // hold_term
    (* purpose = "hold_term C/V/Z/N" *)
    sn74ahct08 ha0 (.a({cc_q[3], cc_q[2], cc_q[1], cc_q[0]}), .b({nld_n, nld_z, nld_v, nld_c}), .y(ht0));
    (* purpose = "hold_term H/M/I" *)
    sn74ahct08 ha1 (.a({1'b0, cc_q[4], cc_q[7], cc_q[5]}), .b({1'b0, nld_i, nld_m, nld_h}), .y(ht1));
    wire [3:0] dn0, dn1;        // cc_dn = ld_term | hold_term
    (* purpose = "cc_dn C/V/Z/N" *)
    sn74ahct32 do0 (.a(lt0), .b(ht0), .y(dn0));
    (* purpose = "cc_dn H/M/I" *)
    sn74ahct32 do1 (.a(lt1), .b(ht1), .y(dn1));
    // assemble the normal next-CC byte (bit6 reserved holds via cc_q[6])
    wire [7:0] cc_dn = {dn1[1], cc_q[6], dn1[0], dn1[2], dn0[3], dn0[2], dn0[1], dn0[0]};
    // positions: [7]=M(dn1[1]) [6]=cc_q[6] [5]=H(dn1[0]) [4]=I(dn1[2]) [3]=N(dn0[3]) [2]=Z(dn0[2]) [1]=V(dn0[1]) [0]=C(dn0[0])

    // ---- reset mux: reset_n ? cc_dn : 0x90, then the register -----------------------
    wire [7:0] cc_d;
    (* purpose = "reset mux [3:0]" *)
    sn74ahct157 rm0 (.a(4'h0), .b(cc_dn[3:0]), .sel(reset_n), .g_n(1'b0), .y(cc_d[3:0]));
    (* purpose = "reset mux [7:4]" *)
    sn74ahct157 rm1 (.a(4'h9), .b(cc_dn[7:4]), .sel(reset_n), .g_n(1'b0), .y(cc_d[7:4]));
    (* purpose = "CC register" *)
    sn74ahct574 ccr (.Q(cc_q), .D(cc_d), .CLK(clk), .OE_n(1'b0));
endmodule
`default_nettype wire
