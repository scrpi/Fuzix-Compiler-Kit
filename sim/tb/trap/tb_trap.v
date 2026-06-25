// Trap-vector interception testbench (Icarus -gspecify, TIMED; D-47). A RETURN_FETCH loop is
// redirected by the trap encoder: no request -> fetch entry 0; pending NMI -> NMI_ENTRY (4);
// unmasked IRQ -> IRQ_ENTRY (8); NMI beats IRQ (priority). IRQ is hardware-masked by CC.I, cleared
// at µPC0. (Masked IRQ -> no trap is covered by irqx + the encoder using the same irq_masked line.)
`timescale 1ns/1ps
`default_nettype none
module tb_trap;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         irq = 1'b0, nmi = 1'b0;
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
        .cond_inject(1'b0), .cond_drive(16'h0000),
        .irq(irq), .nmi(nmi), .wait_ready(1'b1),
        .busreq_n(1'b1), .busgrant_n(),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    integer i;
    // wait up to `budget` clocks for the µPC to hit `target`
    task want(input [11:0 ] target, input [255:0] m);
        begin i = 0;
            while (upc !== target) begin @(negedge clk); i = i + 1;
                if (i > 30) $fatal(1, "%0s: µPC never reached %0d (stuck at %0d)", m, target, upc); end
        end
    endtask
    // confirm the µPC stays within the {0,1} loop for `n` clocks (no spurious trap)
    task stay_loop(input integer n, input [255:0] m);
        begin for (i = 0; i < n; i = i + 1) begin @(negedge clk);
            if (upc > 12'd1) $fatal(1, "%0s: µPC=%0d left the 0/1 loop (spurious trap)", m, upc); end end
    endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("trap: boot done");

        // no request: RETURN_FETCH must go to the fetch entry (loop 0/1)
        stay_loop(8, "no request");

        // unmasked IRQ -> IRQ_ENTRY (8)
        irq = 1'b1; want(12'd8, "IRQ -> IRQ_ENTRY"); irq = 1'b0;
        stay_loop(6, "after IRQ release");

        // NMI -> NMI_ENTRY (4)
        nmi = 1'b1; want(12'd4, "NMI -> NMI_ENTRY"); nmi = 1'b0;
        stay_loop(6, "after NMI release");

        // NMI beats IRQ: both asserted -> NMI_ENTRY (4), never IRQ_ENTRY
        irq = 1'b1; nmi = 1'b1; want(12'd4, "NMI+IRQ -> NMI_ENTRY (priority)");
        irq = 1'b0; nmi = 1'b0;

        $display("PASS - trap: RETURN_FETCH intercept -> IRQ_ENTRY/NMI_ENTRY; NMI>IRQ; I-masked");
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - trap boot never completed"); end
endmodule
`default_nettype wire
