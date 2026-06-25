// Byte-lane integration testbench (Icarus -gspecify, TIMED; D-47) — the whole datapath, proving
// the LEFT_LANE / Z_LANE steer wiring in cpu.v. A directed microprogram (mk_lanex_image.py)
// builds a 16-bit value into SCR1 one byte at a time via Z_LANE (HIGH then LOW), then reads SCR1
// back through every LEFT_LANE mode into SCR2. The bench reads the real register Q's and checks
// the byte-cycle build and the widen/move steers. cond_inject=0, ir_inject=0 (no fetch).
`timescale 1ns/1ps
`default_nettype none
module tb_lanex;
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

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("lanex: boot done; executing ...");

        // µPC 0: Z_DEST=SCR1 FULL16, Z=+1
        @(negedge clk);
        if (upc !== 12'd0) $fatal(1, "step0: µPC=%0d exp 0", upc);

        // 0->1 edge: SCR1 <- 0x0001 (FULL16 load)
        @(negedge clk);
        if (upc !== 12'd1) $fatal(1, "step1: µPC=%0d exp 1", upc);
        if (dut.scr1.q !== 16'h0001) $fatal(1, "SCR1=%04x exp 0001 (FULL16 load)", dut.scr1.q);

        // 1->2 edge: Z_LANE=HIGH, Z=+2 -> SCR1.hi <- 0x02, lo held -> 0x0201
        @(negedge clk);
        if (upc !== 12'd2) $fatal(1, "step2: µPC=%0d exp 2", upc);
        if (dut.scr1.q !== 16'h0201)
            $fatal(1, "SCR1=%04x exp 0201 (Z_LANE=HIGH promotes Z[7:0]=02 to hi, lo held)", dut.scr1.q);

        // 2->3 edge: Z_LANE=LOW, Z=-1 -> SCR1.lo <- 0xFF, hi held -> 0x02FF
        @(negedge clk);
        if (upc !== 12'd3) $fatal(1, "step3: µPC=%0d exp 3", upc);
        if (dut.scr1.q !== 16'h02FF)
            $fatal(1, "SCR1=%04x exp 02FF (Z_LANE=LOW loads lo=FF, hi held)", dut.scr1.q);

        // 3->4 edge: LEFT_LANE=LOW on SCR1(0x02FF) -> Z=0x00FF -> SCR2
        @(negedge clk);
        if (upc !== 12'd4) $fatal(1, "step4: µPC=%0d exp 4", upc);
        if (dut.scr2.q !== 16'h00FF)
            $fatal(1, "SCR2=%04x exp 00FF (LEFT_LANE=LOW zero-extends FF)", dut.scr2.q);

        // 4->5 edge: LEFT_LANE=SIGN_EXT on SCR1(0x02FF) -> Z=0xFFFF -> SCR2
        @(negedge clk);
        if (upc !== 12'd5) $fatal(1, "step5: µPC=%0d exp 5", upc);
        if (dut.scr2.q !== 16'hFFFF)
            $fatal(1, "SCR2=%04x exp FFFF (LEFT_LANE=SIGN_EXT widens FF, vs 00FF for LOW)", dut.scr2.q);

        // 5->6 edge: LEFT_LANE=HIGH_TO_LOW on SCR1(0x02FF) -> Z=0x0002 -> SCR2
        @(negedge clk);
        if (upc !== 12'd6) $fatal(1, "step6: µPC=%0d exp 6", upc);
        if (dut.scr2.q !== 16'h0002)
            $fatal(1, "SCR2=%04x exp 0002 (LEFT_LANE=HIGH_TO_LOW moves hi byte 02 onto low lane)", dut.scr2.q);

        // WAIT holds, and SCR1 was never disturbed by the LEFT reads
        @(negedge clk);
        if (upc !== 12'd6) $fatal(1, "WAIT did not hold at 6 (µPC=%0d)", upc);
        if (dut.scr1.q !== 16'h02FF) $fatal(1, "SCR1 disturbed: %04x exp 02FF", dut.scr1.q);

        $display("PASS - lanex: Z_LANE byte-build SCR1=02FF; LEFT_LANE LOW/SIGN_EXT/HIGH_TO_LOW = 00FF/FFFF/0002");
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - lanex boot never completed"); end
endmodule
`default_nettype wire
