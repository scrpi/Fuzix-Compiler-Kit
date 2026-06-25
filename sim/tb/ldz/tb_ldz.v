// Read-posts-on-Z testbench (Icarus -gspecify, TIMED; D-47) — the load/store foundation. A
// directed microprogram reads a byte from the harness memory into D's low lane AND sets N/Z in
// ONE microword (cond_inject=0, ir_inject=0). Proves: the read byte is on Z[7:0] during /RD
// (combinational bypass, not the stale MDR), Z[15:8] is a defined 0x00, the register latches it,
// the flags capture it, and there is NO bus collision (the ALU PASS_L is suppressed -> no X on Z).
`timescale 1ns/1ps
`default_nettype none
module tb_ldz;
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

    // behavioural memory model (harness; R-SIM-3)
    reg [7:0] mem [0:65535];
    assign d = (rd_n === 1'b0) ? mem[a[15:0]] : 8'bz;
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
        mem[1] = 8'h80;     // a negative byte (N set, Z clear)
        mem[2] = 8'h00;     // zero (Z set)
    end

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("ldz: boot done");

        @(negedge clk);                              // uPC0 (MAR <- +1)
        @(negedge clk);                              // 0->1: MAR=1; now uPC1 = the read
        if (upc !== 12'd1) $fatal(1, "step1: uPC=%0d exp 1", upc);
        if (dut.mar_reg.q !== 16'h0001) $fatal(1, "MAR=%04x exp 0001", dut.mar_reg.q);
        // DURING the read cycle: the byte is on Z (combinational), high byte zero-extended, no X.
        #200;
        if (rd_n !== 1'b0) $fatal(1, "expected /RD asserted during the read word");
        if ($isunknown(z_q)) $fatal(1, "Z bus has X during read (bus collision?) z_q=%h", z_q);
        if (z_q[7:0] !== 8'h80) $fatal(1, "read post: Z[7:0]=%02x exp 80 (mem[1])", z_q[7:0]);
        if (z_q[15:8] !== 8'h00) $fatal(1, "read post: Z[15:8]=%02x exp 00 (zero-extend)", z_q[15:8]);
        if (dut.mi.mdr_q === 8'h80) $fatal(1, "MDR already 80 mid-read — post must be the LIVE byte, not stale MDR");

        @(negedge clk);                              // 1->2: D.low<-80, CC.N/Z, MDR<-80
        if (upc !== 12'd2) $fatal(1, "step2: uPC=%0d exp 2", upc);
        if (dut.d_reg.q[7:0] !== 8'h80) $fatal(1, "A(=D.low)=%02x exp 80 (latched from Z)", dut.d_reg.q[7:0]);
        if (cc_q[3] !== 1'b1) $fatal(1, "CC.N=%b exp 1 (byte 0x80 negative)", cc_q[3]);
        if (cc_q[2] !== 1'b0) $fatal(1, "CC.Z=%b exp 0", cc_q[2]);
        if (dut.mi.mdr_q !== 8'h80) $fatal(1, "MDR=%02x exp 80 (captured on the terminating edge)", dut.mi.mdr_q);

        @(negedge clk);                              // 2->3: MAR=2; uPC3 = read mem[2]=00
        @(negedge clk);                              // 3->4: D.low<-00, CC.Z=1
        if (upc !== 12'd4) $fatal(1, "step4: uPC=%0d exp 4", upc);
        if (dut.d_reg.q[7:0] !== 8'h00) $fatal(1, "A=%02x exp 00", dut.d_reg.q[7:0]);
        if (cc_q[2] !== 1'b1) $fatal(1, "CC.Z=%b exp 1 (byte 0x00)", cc_q[2]);
        if (cc_q[3] !== 1'b0) $fatal(1, "CC.N=%b exp 0", cc_q[3]);

        $display("PASS - ldz: read posts on Z (live byte, zero-ext, no collision); latch + N/Z in one word");
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - ldz boot never completed"); end
endmodule
`default_nettype wire
