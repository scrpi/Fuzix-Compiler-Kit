// Bus-arbiter testbench (Icarus -gspecify, TIMED; D-47). With the CPU idling (WAIT, TAS_LOCK=OFF),
// asserting /BUSREQ must grant the bus: /BUSGRANT asserts and A[23:0]//RD//WR go high-Z so an
// external master owns the bus; deasserting /BUSREQ resumes. (interface.md §4.6, R-IF-4.)
`timescale 1ns/1ps
`default_nettype none
module tb_arbx;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         busreq_n = 1'b1;
    always #1000 clk = ~clk;

    wire [23:0] a;
    wire [7:0]  d;
    wire        rd_n, wr_n, loading, busgrant_n;
    wire [11:0] upc;
    wire [87:0] cw;
    wire [11:0] lut_out;
    wire [7:0]  ir_q;
    wire [15:0] pc_q, z_q;
    wire [7:0]  cc_q;

    cpu #(.FILE(`IMG)) dut (
        .clk(clk), .rst_n(rst_n), .ir_inject(1'b1), .ir_drive(8'h00),
        .cond_inject(1'b1), .cond_drive(16'h0000),
        .irq(1'b0), .nmi(1'b0), .wait_ready(1'b1),
        .busreq_n(busreq_n), .busgrant_n(busgrant_n),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    integer i;
    task settle(input integer n); begin for (i=0;i<n;i=i+1) @(negedge clk); end endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        settle(2);
        // not requested: CPU owns the bus (A driven, /BUSGRANT high)
        if (busgrant_n !== 1'b1) $fatal(1, "idle: /BUSGRANT asserted with no request");
        if ($isunknown(a)) $fatal(1, "idle: A is X (should be driven)");

        // request the bus -> granted: /BUSGRANT low, A//RD//WR tri-stated
        busreq_n = 1'b0; settle(3);
        if (busgrant_n !== 1'b0) $fatal(1, "grant: /BUSGRANT=%b exp 0 after /BUSREQ", busgrant_n);
        if (a    !== 24'bz) $fatal(1, "grant: A=%h not tri-stated", a);
        if (rd_n !== 1'bz)  $fatal(1, "grant: /RD not tri-stated");
        if (wr_n !== 1'bz)  $fatal(1, "grant: /WR not tri-stated");

        // release the request -> CPU resumes, drives the bus again
        busreq_n = 1'b1; settle(3);
        if (busgrant_n !== 1'b1) $fatal(1, "release: /BUSGRANT still asserted");
        if ($isunknown(a)) $fatal(1, "release: A is X (CPU should drive again)");

        $display("PASS - arbx: /BUSREQ -> /BUSGRANT, A//RD//WR tri-stated, then resume");
        $finish;
    end
    initial begin #300000000; $fatal(1, "TIMEOUT - arbx boot never completed"); end
endmodule
`default_nettype wire
