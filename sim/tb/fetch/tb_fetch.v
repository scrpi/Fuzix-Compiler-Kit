// Real-fetch testbench (Icarus -gspecify, TIMED; D-47) — the whole front end end-to-end.
//
// This is the first bench where the opcode is NOT injected: ir_inject=0 and ir_drive=0, so
// IR can only become the opcode by a REAL FETCH through the datapath that now exists —
// PC -> address mux -> MMU identity map -> external bus -> memory model -> MDR -> IR. The
// memory is a behavioural model in the harness, outside the CPU under test (R-SIM-3).
//
// Directed fetch microcode (sim/tb/fetch/mk_fetch_image.py): read mem[PC] into MDR while PC
// counts, latch MDR into IR, then DISPATCH_IR. The bench loads opcode 0x42 at address 0 and
// checks, step by step, that the byte travels memory -> MDR -> IR and the dispatch lands on
// the opcode-LUT target — i.e. that the machine fetched and decoded a real instruction.
`timescale 1ns/1ps
`default_nettype none
module tb_fetch;
    localparam [7:0]  OPCODE = 8'h42;       // the instruction byte placed in memory at 0
    localparam [11:0] TARGET = 12'd48;      // its opcode-LUT dispatch target (mk_fetch_image.py)

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    always #1000 clk = ~clk;                // 2 us period (slow boot clock)

    wire [23:0] a;
    wire [7:0]  d;
    wire        rd_n, wr_n;
    wire        loading;
    wire [11:0] upc;
    wire [87:0] cw;
    wire [11:0] lut_out;
    wire [7:0]  ir_q;
    wire [15:0] pc_q;

    // ir_inject=0 -> REAL fetch (IR from MDR, never from ir_drive). cond_drive unused (no branch).
    cpu #(.FILE(`IMG)) dut (
        .clk(clk), .rst_n(rst_n), .ir_inject(1'b0), .ir_drive(8'h00), .cond_drive(16'h0000),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q), .pc_q(pc_q)
    );

    // --- behavioural memory model (the harness, outside the DUT — R-SIM-3) -------------
    reg [7:0] mem [0:65535];
    assign d = (rd_n === 1'b0) ? mem[a[15:0]] : 8'bz;   // device drives D while /RD low
    // capture on the /WR rising edge, but never on the power-on x->1 settle (address/data
    // still unknown) — a real device sees a clean strobe, not that sim artifact.
    always @(posedge wr_n) if (!$isunknown({a[15:0], d})) mem[a[15:0]] <= d;

    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
        mem[0] = OPCODE;                                // the program: one instruction at 0
    end

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;                                   // release boot reset
        wait (loading == 1'b0);                         // boot copy complete; µPC released at 0
        $display("fetch: boot done; PC=%0d, fetching ...", pc_q);

        // step 0: the fetch-read microword is at µPC 0
        @(negedge clk);
        if (upc !== 12'd0) $fatal(1, "step0: µPC=%0d, expected 0", upc);

        // step 1 (µPC 1): the 0->1 edge latched mem[PC] into MDR and advanced PC
        @(negedge clk);
        if (upc !== 12'd1) $fatal(1, "step1: µPC=%0d, expected 1", upc);
        if (dut.mi.mdr_q !== OPCODE) $fatal(1, "fetch: MDR=%02x, expected %02x from mem[0]", dut.mi.mdr_q, OPCODE);
        if (pc_q !== 16'd1) $fatal(1, "fetch: PC=%0d, expected 1 (PC-direct read advances PC)", pc_q);

        // step 2 (µPC 2): the 1->2 edge latched MDR into IR; the LUT now sees the real opcode
        @(negedge clk);
        if (upc !== 12'd2) $fatal(1, "step2: µPC=%0d, expected 2", upc);
        if (ir_q !== OPCODE) $fatal(1, "fetch: IR=%02x, expected %02x (opcode from memory, not injected)", ir_q, OPCODE);
        if (lut_out !== TARGET) $fatal(1, "dispatch: lut_out=%0d, expected %0d", lut_out, TARGET);

        // step 3: DISPATCH_IR vectored the micro-PC to the opcode's handler
        @(negedge clk);
        if (upc !== TARGET) $fatal(1, "dispatch: µPC=%0d, expected %0d (lut[{0,%02x}])", upc, TARGET, OPCODE);

        // ...and WAIT holds it there
        @(negedge clk);
        if (upc !== TARGET) $fatal(1, "WAIT: µPC=%0d did not hold at %0d", upc, TARGET);

        $display("PASS - real fetch: mem[0]=%02x -> MDR -> IR -> DISPATCH -> µPC %0d (PC advanced to %0d)",
                 OPCODE, TARGET, pc_q);
        $finish;
    end

    initial begin
        #300000000;                                     // > boot time (~106 ms)
        $fatal(1, "TIMEOUT - boot never completed");
    end
endmodule
`default_nettype wire
