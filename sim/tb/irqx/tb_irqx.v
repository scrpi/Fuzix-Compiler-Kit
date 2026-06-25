// Microcondition integration testbench (Icarus -gspecify, TIMED; D-47) — the internal/external
// sequencer microconditions IRQ/NMI/WAIT_READY (cond[9..11]), through the whole datapath. The
// bench drives the real condition lines and watches the µPC walk through three gates with
// cond_inject=0 (no injection): it spins until IRQ, then until NMI, then stalls until the bus is
// ready — proving each line reaches the condition mux and branches.
`timescale 1ns/1ps
`default_nettype none
module tb_irqx;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         irq = 1'b0, nmi = 1'b0, wait_ready = 1'b0;
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
        .irq(irq), .nmi(nmi), .wait_ready(wait_ready),
        .busreq_n(1'b1), .busgrant_n(),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    integer i;
    task settle(input integer n);  // advance n clocks
        begin for (i = 0; i < n; i = i + 1) @(negedge clk); end
    endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("irqx: boot done");

        // --- µPC0 clears CC.I (unmask IRQ); with no requests, it spins in the IRQ gate (1/2) ---
        settle(6);
        if (upc < 12'd1 || upc > 12'd2) $fatal(1, "IRQ gate: µPC=%0d left the 1/2 spin with irq=0", upc);

        // --- assert IRQ (now unmasked): the machine must reach the NMI gate (4/5) -------------
        irq = 1'b1;
        settle(4);
        if (upc < 12'd4 || upc > 12'd5) $fatal(1, "IRQ branch: µPC=%0d exp the 4/5 NMI spin", upc);

        // --- assert NMI: the machine must reach the WAIT_READY gate (7) --------
        nmi = 1'b1;
        settle(4);
        if (upc !== 12'd7) $fatal(1, "NMI branch: µPC=%0d exp 7 (WAIT_READY gate)", upc);
        // wait_ready=0 -> `if not wait-ready` keeps it stalled at 7
        settle(3);
        if (upc !== 12'd7) $fatal(1, "WAIT_READY: µPC=%0d left 7 with wait_ready=0", upc);

        // --- assert WAIT_READY: fall through to the WAIT at 8 -----------------
        wait_ready = 1'b1;
        settle(2);
        if (upc !== 12'd8) $fatal(1, "WAIT_READY branch: µPC=%0d exp 8", upc);

        $display("PASS - irqx: IRQ(I-masked)/NMI/WAIT_READY conditions gate the sequencer (cond[9..11])");
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - irqx boot never completed"); end
endmodule
`default_nettype wire
