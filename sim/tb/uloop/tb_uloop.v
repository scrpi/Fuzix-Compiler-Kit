// ULOOP integration testbench (Icarus -gspecify, TIMED; D-47) — the micro-loop counter and the
// ULOOP microcondition, through the whole datapath. A directed microprogram (mk_uloop_image.py)
// loads uloop with 3 and runs a body that increments X, branching on the REAL uloop terminal
// (cond_inject=0). The bench checks the body ran exactly 3 times (X==3, and the µPC held at the
// loop word for 3 cycles then fell through).
`timescale 1ns/1ps
`default_nettype none
module tb_uloop;
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

    integer loops = 0;

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("uloop: boot done");

        @(negedge clk);                                  // uPC0
        @(negedge clk);                                  // 0->1 : X<-0
        @(negedge clk);                                  // 1->2 : SCR1<-2
        @(negedge clk);                                  // 2->3 : uloop<-3, enter loop
        if (upc !== 12'd3) $fatal(1, "did not enter loop at 3 (uPC=%0d)", upc);

        // count how many cycles the µPC stays at the loop word (3 expected)
        while (upc == 12'd3) begin
            loops = loops + 1;
            @(negedge clk);
            if (loops > 20) $fatal(1, "loop never terminated (uPC stuck at 3)");
        end
        if (loops !== 3) $fatal(1, "loop body ran %0d times, exp 3 (uloop terminal off)", loops);
        if (upc !== 12'd4) $fatal(1, "fell through to uPC=%0d exp 4", upc);
        if (dut.x_reg.q !== 16'd3) $fatal(1, "X=%0d exp 3 (body increments)", dut.x_reg.q);

        @(negedge clk);                                  // 4->5 : SCR2<-X
        if (dut.scr2.q !== 16'd3) $fatal(1, "SCR2=%0d exp 3", dut.scr2.q);

        @(negedge clk);
        if (upc !== 12'd5) $fatal(1, "WAIT did not hold at 5 (uPC=%0d)", upc);

        $display("PASS - uloop: real ULOOP terminal -> loop body ran exactly 3 times (X=3)");
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - uloop boot never completed"); end
endmodule
`default_nettype wire
