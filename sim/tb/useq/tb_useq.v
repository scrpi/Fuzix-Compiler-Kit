// CALL/RETURN + µSR testbench (Icarus -gspecify, TIMED; D-47). Walks a directed control store
// where a shared leaf routine is called from three sites; checks each RETURN lands on the
// caller's NEXT microaddress — proving the µSR is read (different returns: 1, 2, 16) and that the
// µPC+1 adder carries across a nibble (0x0F -> 0x10).
`timescale 1ns/1ps
`default_nettype none
module tb_useq;
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
        .clk(clk), .rst_n(rst_n), .ir_inject(1'b1), .ir_drive(8'h00),
        .cond_inject(1'b1), .cond_drive(16'h0000),
        .irq(1'b0), .nmi(1'b0), .wait_ready(1'b1),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    task step(input [11:0] exp, input [255:0] m);
        begin @(negedge clk);
            if (upc !== exp) $fatal(1, "%0s: uPC=%0d exp %0d", m, upc, exp); end
    endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("useq: boot done");

        step(12'd0,  "uPC0 (CALL)");
        step(12'd20, "1st CALL -> routine 20");
        step(12'd21, "routine -> RETURN word");
        step(12'd1,  "RETURN -> caller+1 = 1 (uSR read)");
        step(12'd20, "2nd CALL -> routine 20");
        step(12'd21, "routine -> RETURN word");
        step(12'd2,  "RETURN -> caller+1 = 2 (uSR is read, not constant)");
        step(12'd15, "JUMP -> 15");
        step(12'd20, "3rd CALL (at 0x0F) -> routine 20");
        step(12'd21, "routine -> RETURN word");
        step(12'd16, "RETURN -> 0x0F+1 = 0x10 (uPC+1 adder carry)");
        step(12'd16, "WAIT holds at 16");

        $display("PASS - useq: CALL/RETURN + µSR — returns to 1/2/16 (uSR read; +1 carries 0x0F->0x10)");
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - useq boot never completed"); end
endmodule
`default_nettype wire
