// Privileged-M/I integration testbench (Icarus -gspecify, TIMED; D-47) — the whole datapath,
// proving the decoder->CC wiring of the privileged M/I controls (findings #1/#3). A directed
// microprogram (mk_ccx_image.py) drives CC_MI_LOAD=SET_I/CLR_I and a CC_WRITE_SRC=WHOLE_Z
// restore, and the bench reads the real cc_q to check: SET_I/CLR_I change I alone (M held), a
// whole CC write restores M/I, and a privileged M/I write in user mode is ignored (isa.md §8.7).
`timescale 1ns/1ps
`default_nettype none
module tb_ccx;
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
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("ccx: boot done; CC=%02x (reset = supervisor, IRQ masked)", cc_q);
        if (cc_q !== 8'h90) $fatal(1, "reset CC=%02x exp 90", cc_q);

        // µPC 0: CLR_I
        @(negedge clk);
        if (upc !== 12'd0) $fatal(1, "step0: µPC=%0d exp 0", upc);

        // 0->1 edge: CLR_I -> I<-0, M held (supervisor)
        @(negedge clk);
        if (upc !== 12'd1) $fatal(1, "step1: µPC=%0d exp 1", upc);
        if (cc_q[4] !== 1'b0) $fatal(1, "CLI: I=%b exp 0", cc_q[4]);
        if (cc_q[7] !== 1'b1) $fatal(1, "CLI clobbered M=%b exp 1 (must hold)", cc_q[7]);

        // 1->2 edge: SET_I -> I<-1, M held
        @(negedge clk);
        if (upc !== 12'd2) $fatal(1, "step2: µPC=%0d exp 2", upc);
        if (cc_q[4] !== 1'b1) $fatal(1, "SEI: I=%b exp 1", cc_q[4]);
        if (cc_q[7] !== 1'b1) $fatal(1, "SEI clobbered M=%b exp 1 (must hold)", cc_q[7]);

        // 2->3 edge: WHOLE_Z(0) -> CC<-0x00 ; M<-0 (drop to user), I<-0
        @(negedge clk);
        if (upc !== 12'd3) $fatal(1, "step3: µPC=%0d exp 3", upc);
        if (cc_q !== 8'h00) $fatal(1, "WHOLE_Z restore: CC=%02x exp 00 (M/I + flags from Z)", cc_q);

        // 3->4 edge: SET_I in USER mode -> ignored (privilege interlock)
        @(negedge clk);
        if (upc !== 12'd4) $fatal(1, "step4: µPC=%0d exp 4", upc);
        if (cc_q[4] !== 1'b0) $fatal(1, "priv: user SET_I set I=%b (must stay 0)", cc_q[4]);
        if (cc_q[7] !== 1'b0) $fatal(1, "priv: M=%b exp 0 (still user)", cc_q[7]);

        // WAIT holds
        @(negedge clk);
        if (upc !== 12'd4) $fatal(1, "WAIT did not hold at 4 (µPC=%0d)", upc);

        $display("PASS - ccx: SET_I/CLR_I change I alone (M held); WHOLE_Z restores M/I; user M/I write ignored");
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - ccx boot never completed"); end
endmodule
`default_nettype wire
