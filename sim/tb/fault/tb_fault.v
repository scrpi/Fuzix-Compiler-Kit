// Fault-detector testbench (Icarus -gspecify, TIMED; D-47). The opcode LUT carries a privileged
// bit (lut_hi[4]) and a VALID bit (lut_hi[5]); the detectors form PRIV_VIOLATION = priv & ~CC.M
// and ILLEGAL_OPCODE = ~VALID -> cond[13]/[14]. The bench injects page-1 opcodes (DISPATCH_PAGE=1
// in the image) and reads the detectors at CC.M=1 (supervisor) and CC.M=0 (user).
`timescale 1ns/1ps
`default_nettype none
module tb_fault;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg  [7:0]  ir_drive = 8'h07;       // SEI (page1 0x07) — a privileged opcode
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
        .clk(clk), .rst_n(rst_n), .ir_inject(1'b1), .ir_drive(ir_drive),
        .cond_inject(1'b0), .cond_drive(16'h0000),
        .irq(1'b0), .nmi(1'b0), .wait_ready(1'b1),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    integer errors = 0;
    task chk(input got, input exp, input [255:0] m);
        begin if (got !== exp) begin $display("FAIL %0s: %b exp %b", m, got, exp); errors=errors+1; end end
    endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("fault: boot done");

        // µPC0: supervisor (CC.M=1), page-1 index = SEI (privileged) -> NO violation; SEI is bound.
        @(negedge clk); #200;
        if (upc !== 12'd0) $fatal(1, "step0 µPC=%0d exp 0", upc);
        if (cc_q[7] !== 1'b1) $fatal(1, "expected supervisor (M=1) at start");
        chk(dut.priv_violation, 1'b0, "supervisor: priv opcode does NOT violate");
        chk(dut.illegal_op,     1'b0, "SEI is a bound opcode (VALID)");

        // µPC1 clears M -> user; µPC2 (M=0): a privileged opcode now violates.
        @(negedge clk);                 // 0->1
        @(negedge clk); #200;           // 1->2 : M=0 now
        if (cc_q[7] !== 1'b0) $fatal(1, "expected user (M=0) after WHOLE_Z clear");
        chk(dut.priv_violation, 1'b1, "user: privileged SEI violates -> cond[13]");
        chk(dut.illegal_op,     1'b0, "SEI still bound");

        // an unbound page-1 byte (0xFF) -> ILLEGAL; not privileged.
        ir_drive = 8'hFF; #200;
        chk(dut.illegal_op,     1'b1, "unbound opcode 0xFF -> ILLEGAL cond[14]");
        chk(dut.priv_violation, 1'b0, "unbound opcode is not privileged");

        // a bound, non-privileged page-1 byte (0x00 = DAA) -> neither fault.
        ir_drive = 8'h00; #200;
        chk(dut.illegal_op,     1'b0, "DAA (page1 0x00) is bound");
        chk(dut.priv_violation, 1'b0, "DAA is not privileged");

        if (errors == 0)
            $display("PASS - fault: PRIV_VIOLATION (priv & ~CC.M) and ILLEGAL_OPCODE (~VALID) -> cond[13]/[14]");
        else
            $fatal(1, "fault: %0d check(s) FAILED", errors);
        $finish;
    end

    initial begin #300000000; $fatal(1, "TIMEOUT - fault boot never completed"); end
endmodule
`default_nettype wire
