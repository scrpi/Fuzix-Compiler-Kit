// Execute-and-branch testbench (Icarus -gspecify, TIMED; D-47) — the whole datapath, and the
// milestone that closes cond_drive: the machine computes, latches CC, and branches on the
// REAL condition. cond_inject=0, so the branch conditions come from CC, not the bench.
//
// Directed microprogram (sim/tb/exec/mk_exec_image.py): load SCR1=1; SUB SCR1-1 -> 0 (CC.Z=1,
// CC.C=0); BRANCH on C (must NOT take); BRANCH on Z (must take) -> 10. The bench checks the
// computed register/flags and that the µPC walk follows the real conditions.
`timescale 1ns/1ps
`default_nettype none
module tb_exec;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    always #1000 clk = ~clk;

    wire [23:0] a;
    wire [7:0]  d;
    wire        rd_n, wr_n, loading;
    wire [11:0] upc;
    wire [87:0] cw;
    wire [11:0] lut_out;
    wire [7:0]  ir_q;
    wire [15:0] pc_q, z_q;
    wire [7:0]  cc_q;

    // cond_inject=0 -> the branch conditions are CC-derived (REAL). ir_inject=0 (unused: no fetch).
    cpu #(.FILE(`IMG)) dut (
        .clk(clk), .rst_n(rst_n), .ir_inject(1'b0), .ir_drive(8'h00),
        .cond_inject(1'b0), .cond_drive(16'h0000),
        .irq(1'b0), .nmi(1'b0), .wait_ready(1'b1),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("exec: boot done; executing ...");

        // µPC 0: PASS_R(+1) -> Z=1, Z_DEST=SCR1
        @(negedge clk);
        if (upc !== 12'd0) $fatal(1, "step0: µPC=%0d exp 0", upc);

        // µPC 1: the 0->1 edge latched SCR1 = 1
        @(negedge clk);
        if (upc !== 12'd1) $fatal(1, "step1: µPC=%0d exp 1", upc);
        if (dut.scr1.q !== 16'd1) $fatal(1, "SCR1=%04x exp 0001 (loaded from ALU via Z)", dut.scr1.q);

        // µPC 2: the 1->2 edge ran SUB 1-1=0 and latched CC (Z=1, C=0)
        @(negedge clk);
        if (upc !== 12'd2) $fatal(1, "step2: µPC=%0d exp 2", upc);
        if (cc_q[2] !== 1'b1) $fatal(1, "CC.Z=%b exp 1 (1-1=0)", cc_q[2]);
        if (cc_q[0] !== 1'b0) $fatal(1, "CC.C=%b exp 0 (no borrow)", cc_q[0]);

        // µPC 3: BRANCH on C(=0) did NOT take -> fell through to 3
        @(negedge clk);
        if (upc !== 12'd3) $fatal(1, "BRANCH C wrongly taken: µPC=%0d exp 3 (C=0 must not branch)", upc);

        // µPC 10: BRANCH on Z(=1) took -> 10  (the real-condition branch)
        @(negedge clk);
        if (upc !== 12'd10) $fatal(1, "BRANCH Z not taken: µPC=%0d exp 10 (CC.Z=1 must branch)", upc);

        // phase 2 — µPC 11: the 10->11 edge ran SUB 0-1=0xFFFF (CC.Z=0, CC.C=1)
        @(negedge clk);
        if (upc !== 12'd11) $fatal(1, "step11: µPC=%0d exp 11", upc);
        if (cc_q[2] !== 1'b0) $fatal(1, "CC.Z=%b exp 0 (0-1=0xFFFF)", cc_q[2]);
        if (cc_q[0] !== 1'b1) $fatal(1, "CC.C=%b exp 1 (0-1 borrows)", cc_q[0]);

        // µPC 12: BRANCH on Z(=0) did NOT take -> fell through to 12 (the OTHER sense of Z)
        @(negedge clk);
        if (upc !== 12'd12) $fatal(1, "BRANCH Z wrongly taken: µPC=%0d exp 12 (Z=0 must not branch)", upc);

        // µPC 20: BRANCH on C(=1) took -> 20 (the OTHER sense of C)
        @(negedge clk);
        if (upc !== 12'd20) $fatal(1, "BRANCH C not taken: µPC=%0d exp 20 (CC.C=1 must branch)", upc);

        // WAIT holds
        @(negedge clk);
        if (upc !== 12'd20) $fatal(1, "WAIT did not hold at 20 (µPC=%0d)", upc);

        $display("PASS - exec: real CC conditions select correctly — Z taken@1/not@0, C not@0/taken@1 (cond_drive closed)");
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - boot never completed"); end
endmodule
`default_nettype wire
