// TAS_LOCK testbench (Icarus -gspecify, TIMED; D-47). With TAS_LOCK asserted (a read-modify-write
// holding the bus, isa.md §9), a pending /BUSREQ must NOT be granted — the CPU keeps the bus
// across the locked cycle so the RMW is atomic. (interface.md §4.6.)
`timescale 1ns/1ps
`default_nettype none
module tb_tasx;
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
        // the held microword asserts TAS_LOCK: a /BUSREQ must be refused (bus held for the RMW)
        busreq_n = 1'b0; settle(4);
        if (busgrant_n !== 1'b1) $fatal(1, "TAS_LOCK: /BUSGRANT=%b — bus granted during a locked RMW", busgrant_n);
        if ($isunknown(a)) $fatal(1, "TAS_LOCK: A tri-stated during a locked RMW (must stay driven)");

        $display("PASS - tasx: TAS_LOCK holds the bus — /BUSREQ refused during the locked RMW");
        $finish;
    end
    initial begin #300000000; $fatal(1, "TIMEOUT - tasx boot never completed"); end
endmodule
`default_nettype wire
