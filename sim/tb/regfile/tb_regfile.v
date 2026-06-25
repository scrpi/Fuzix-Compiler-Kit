// Register-file integration testbench (Icarus -gspecify, TIMED; D-47) — the rest of the
// architectural register file and ACTIVE_SP banking, through the whole datapath. A directed
// microprogram (mk_regfile_image.py) loads/drives X (with an off-bus +1), Y, and D (incl. a
// byte lane), then loads SSP/USP and reads ACTIVE_SP in supervisor and in user, so the bench can
// confirm the real register Q's and the CC.M-resolved bank. cond_inject=0, ir_inject=0.
`timescale 1ns/1ps
`default_nettype none
module tb_regfile;
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

    cpu #(.FILE(`IMG)) dut (
        .clk(clk), .rst_n(rst_n), .ir_inject(1'b0), .ir_drive(8'h00),
        .cond_inject(1'b0), .cond_drive(16'h0000),
        .irq(1'b0), .nmi(1'b0), .wait_ready(1'b1),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    integer errors = 0;
    task chk(input [15:0] got, input [15:0] exp, input [255:0] m);
        begin if (got !== exp) begin
            $display("FAIL %0s: %04x exp %04x (uPC=%0d)", m, got, exp, upc); errors=errors+1; end end
    endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("regfile: boot done; CC=%02x", cc_q);

        @(negedge clk);                                  // uPC0 presented
        @(negedge clk);                                  // 0->1: X <- 2
        chk(dut.x_reg.q, 16'h0002, "X load");
        @(negedge clk);                                  // 1->2: X++ -> 3
        chk(dut.x_reg.q, 16'h0003, "X off-bus ++");
        @(negedge clk);                                  // 2->3: SCR1 <- X
        chk(dut.scr1.q, 16'h0003, "SCR1 <- X (LEFT drive)");
        @(negedge clk);                                  // 3->4: Y <- -1
        chk(dut.y_reg.q, 16'hFFFF, "Y load");
        @(negedge clk);                                  // 4->5: SCR2 <- Y
        chk(dut.scr2.q, 16'hFFFF, "SCR2 <- Y (LEFT drive)");
        @(negedge clk);                                  // 5->6: D <- 1
        chk(dut.d_reg.q, 16'h0001, "D full16 load");
        @(negedge clk);                                  // 6->7: D.high <- FF (Z_LANE=HIGH)
        chk(dut.d_reg.q, 16'hFF01, "D byte-lane high load");
        @(negedge clk);                                  // 7->8: SSP <- 2
        chk(dut.ssp_reg.q, 16'h0002, "SSP load");
        @(negedge clk);                                  // 8->9: USP <- 1
        chk(dut.usp_reg.q, 16'h0001, "USP load");
        @(negedge clk);                                  // 9->10: SCR1 <- ACTIVE_SP (supervisor=SSP)
        chk(dut.scr1.q, 16'h0002, "ACTIVE_SP -> SSP (supervisor)");
        if (cc_q[7] !== 1'b1) $fatal(1, "expected supervisor before the CC clear (M=%b)", cc_q[7]);
        @(negedge clk);                                  // 10->11: CC <- 0 (drop to user)
        if (cc_q[7] !== 1'b0) $fatal(1, "WHOLE_Z did not drop to user (M=%b)", cc_q[7]);
        @(negedge clk);                                  // 11->12: SCR2 <- ACTIVE_SP (user=USP)
        chk(dut.scr2.q, 16'h0001, "ACTIVE_SP -> USP (user)");

        @(negedge clk);
        if (upc !== 12'd12) $fatal(1, "WAIT did not hold at 12 (uPC=%0d)", upc);

        if (errors == 0)
            $display("PASS - regfile: X(load/++)/Y/D(+lane) drive LEFT; ACTIVE_SP = SSP(super)/USP(user)");
        else
            $fatal(1, "regfile: %0d check(s) FAILED", errors);
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - regfile boot never completed"); end
endmodule
`default_nettype wire
