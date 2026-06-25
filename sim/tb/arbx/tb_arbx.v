// Bus-arbiter testbench (Icarus -gspecify, TIMED; D-47). The CPU runs a LIVE non-WAIT loop (the
// µPC walks, PC counts, CC + SCR1 mutate every cycle). Asserting /BUSREQ must (a) grant the bus —
// /BUSGRANT asserts and A[23:0]//RD//WR go high-Z so an external master owns the bus — AND (b)
// STALL the core: while the grant is held, the µPC, PC, CC and the scratch register must not
// change (interface.md §4.6, R-IF-4). Deasserting /BUSREQ resumes both the bus and the core.
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

    // snapshots of the architectural state, for the freeze check
    reg [11:0] s_upc;  reg [15:0] s_pc, s_z, s_scr1;  reg [7:0] s_cc;
    task snap; begin s_upc=upc; s_pc=pc_q; s_z=z_q; s_cc=cc_q; s_scr1=dut.scr1_w; end endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        settle(2);

        // --- the core is LIVE: with no request, the loop must advance the µPC and the PC ---------
        if (busgrant_n !== 1'b1) $fatal(1, "idle: /BUSGRANT asserted with no request");
        if ($isunknown(a))       $fatal(1, "idle: A is X (should be driven)");
        // PC is a monotonic counter here, so its advance is the unambiguous liveness signal (the
        // µPC/Z merely oscillate with the 2-word loop's even period, so they are not used here).
        snap;
        settle(2);
        if (pc_q === s_pc)  $fatal(1, "pre-grant: PC did not advance (stream not live: PC=%0d)", pc_q);

        // --- request the bus -> granted: /BUSGRANT low, A//RD//WR tri-stated --------------------
        busreq_n = 1'b0; settle(3);
        if (busgrant_n !== 1'b0) $fatal(1, "grant: /BUSGRANT=%b exp 0 after /BUSREQ", busgrant_n);
        if (a    !== 24'bz) $fatal(1, "grant: A=%h not tri-stated", a);
        if (rd_n !== 1'bz)  $fatal(1, "grant: /RD not tri-stated");
        if (wr_n !== 1'bz)  $fatal(1, "grant: /WR not tri-stated");

        // --- and the core is STALLED: state must not change while the grant is held -------------
        snap;
        settle(6);                          // hold the grant across several clocks
        if (upc    !== s_upc)  $fatal(1, "grant: µPC moved during a held grant (%0d -> %0d)", s_upc, upc);
        if (pc_q   !== s_pc)   $fatal(1, "grant: PC changed during a held grant (%0d -> %0d)", s_pc, pc_q);
        if (cc_q   !== s_cc)   $fatal(1, "grant: CC changed during a held grant (%02x -> %02x)", s_cc, cc_q);
        if (z_q    !== s_z)    $fatal(1, "grant: Z changed during a held grant (%04x -> %04x)", s_z, z_q);
        if (dut.scr1_w !== s_scr1) $fatal(1, "grant: SCR1 changed during a held grant (%04x -> %04x)", s_scr1, dut.scr1_w);
        // and no architectural state floated/went X while stalled (per-signal: a wide concat into
        // $isunknown mixing a hierarchical ref trips an Icarus quirk).
        if ($isunknown(upc) || $isunknown(pc_q) || $isunknown(cc_q) ||
            $isunknown(z_q)  || $isunknown(dut.scr1_w))
            $fatal(1, "grant: architectural state went X/Z during a held grant");

        // --- release the request -> CPU resumes: bus driven again AND the core runs again -------
        busreq_n = 1'b1; settle(3);
        if (busgrant_n !== 1'b1) $fatal(1, "release: /BUSGRANT still asserted");
        if ($isunknown(a)) $fatal(1, "release: A is X (CPU should drive again)");
        snap;
        settle(2);
        if (pc_q === s_pc) $fatal(1, "release: PC did not resume advancing (PC=%0d)", pc_q);

        $display("PASS - arbx: /BUSREQ -> /BUSGRANT (A//RD//WR tri-stated), a held grant STALLS the core, then resume");
        $finish;
    end
    initial begin #300000000; $fatal(1, "TIMEOUT - arbx boot never completed"); end
endmodule
`default_nettype wire
