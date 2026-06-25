// uloop — the micro-loop counter (microcode.md §2; control_word.toml ULOOP_CTRL). Structural
// netlist of real chips (R-SIM-1, R-SIM-5). Its terminal feeds the ULOOP microcondition (cond[8]),
// which `uloop-- ; if not uloop.zero goto L` branches on — the MUL / multi-bit-shift / PSHS-PULS
// loops.
//
// LOAD VALUE — a deliberate design decision. The control word carries no loop-count field
// (ULOOP_CTRL is just HOLD / LOAD / DECREMENT); the assembler's `n -> uloop` sets ULOOP_CTRL=LOAD
// and discards the literal n. So the count must ride a bus: this counter loads from the Z-bus low
// bits, i.e. whatever a prior microword posted on Z (e.g. the multi-bit shift's `SCR1 <- [PC]`
// posts the shift count n). The constant generator can't make every count, so a fixed-constant
// load source would not serve the variable-n shifts; the Z bus does.
//
// HOW IT COUNTS — the '163 is an UP counter, so a decrement-to-zero loop is realized by loading
// the one's-complement ~n and counting UP to a fixed terminal. With a 5-bit counter, loading ~n
// (= 31 - n) and counting up, the value q[4:1] first reaches all-ones (count = 30) on the n-th
// iteration — so `uloop.zero` (the terminal) asserts there and the body runs exactly n times. The
// condition is evaluated combinationally in the same microword as `uloop--`, so the one's-
// complement load already accounts for that one-cycle lead. 5 bits covers every ISA loop (n<=16).
//
// Structure (the BOM): 1x sn74ahct139 (ULOOP_CTRL decode), 1x sn74ahct04 (~Z load value +
// count-enable sense), 2x cd74act163 (the 5-bit up-counter), 2x sn74ahct08 (the q[4:1] terminal).
`timescale 1ns/1ps
`default_nettype none
module uloop (
    input  wire       clk,
    input  wire       reset_n,        // synchronous clear -> 0 (deterministic power-on)
    input  wire [1:0] uloop_ctrl,     // ULOOP_CTRL: HOLD=0, LOAD=1, DECREMENT=2
    input  wire [4:0] z_lo,           // load source = Z[4:0] (the loop count n)
    output wire       uloop_zero      // terminal: the body has run n times
);
    // ---- ULOOP_CTRL decode (2->4): ctl_n[1]=LOAD (/PE), ctl_n[2]=DECREMENT ------
    wire [3:0] ctl_n;
    (* purpose = "ULOOP_CTRL decode" *)
    sn74ahct139 d (.g1_n(1'b0), .a1(uloop_ctrl[0]), .b1(uloop_ctrl[1]), .y1(ctl_n),
                   .g2_n(1'b1), .a2(1'b0), .b2(1'b0), .y2());
    wire load_n = ctl_n[1];

    // ---- ~Z load value + count-enable (DECREMENT) -------------------------------
    wire [5:0] iv;
    (* purpose = "~Z load value; count-enable" *)
    sn74ahct04 inv (.a({ctl_n[2], z_lo[4], z_lo[3], z_lo[2], z_lo[1], z_lo[0]}), .y(iv));
    wire [4:0] pload    = iv[4:0];     // ~Z[4:0]
    wire       count_en = iv[5];       // ~ctl_n[2] = DECREMENT active

    // ---- 5-bit up-counter: load ~Z / count / hold; sync clear on reset ----------
    // c1 is a 4-bit '163 of which only bit 0 is the counter's bit-4; its top 3 bits load 0 and
    // never advance (the count terminates at 30, before they could).
    wire [4:0] q;
    wire [3:0] c1q;
    wire rco_lo;
    (* purpose = "uloop count [3:0]" *)
    cd74act163 c0 (.clk(clk), .clr_n(reset_n), .load_n(load_n), .enp(count_en), .ent(count_en),
                   .p(pload[3:0]), .q(q[3:0]), .rco(rco_lo));
    (* purpose = "uloop count [4]" *)
    cd74act163 c1 (.clk(clk), .clr_n(reset_n), .load_n(load_n), .enp(count_en), .ent(rco_lo),
                   .p({3'b000, pload[4]}), .q(c1q), .rco());
    assign q[4] = c1q[0];

    // ---- terminal: q[4:1] all-ones (count 30) -> uloop.zero ----------------------
    // q[4:1]==1111 first occurs at count 30 (the n-th iteration); count never reaches 31 because
    // the branch falls through there. Two pair-ANDs then a cross-package merge (no intra-package
    // feedback).
    wire [3:0] t;
    (* purpose = "uloop terminal pairs" *)
    sn74ahct08 ta (.a({2'b00, q[3], q[1]}), .b({2'b00, q[4], q[2]}), .y(t));
    wire [3:0] zt;
    (* purpose = "uloop terminal merge" *)
    sn74ahct08 tb (.a({3'b000, t[0]}), .b({3'b000, t[1]}), .y(zt));
    assign uloop_zero = zt[0];
endmodule
`default_nettype wire
