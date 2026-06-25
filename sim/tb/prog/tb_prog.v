// End-to-end production-microcode testbench (Icarus -gspecify, TIMED; D-47). This is the
// milestone: the CPU boots the REAL blip.uc image and runs a real program out of harness memory
// with NO injection (ir_inject=0, cond_inject=0). It proves the whole front-to-back loop closes —
// single-cycle FETCH -> opcode-LUT dispatch -> execute (read operand, post on Z, latch + flags) ->
// RETURN_FETCH -> next FETCH.
//
// Program: two `LD A,$nn` (page0 0x00; routine `A <- [PC]; PC++ : nz, v=0 ; return to fetch`):
//   mem: 00 80   00 05    ->   A<-0x80 (N=1), then A<-0x05 (N=0), PC walks 0..4.
`timescale 1ns/1ps
`default_nettype none
module tb_prog;
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

    reg [7:0] mem [0:65535];
    assign d = (rd_n === 1'b0) ? mem[a[15:0]] : 8'bz;
    always @(posedge wr_n) if (!$isunknown({a[15:0], d})) mem[a[15:0]] <= d;
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
        mem[0] = 8'h00; mem[1] = 8'h80;   // LD A,$80
        mem[2] = 8'h00; mem[3] = 8'h05;   // LD A,$05
    end

    // wait until D.low (=A) reaches `val`, or fail after `budget` clocks
    task wait_a(input [7:0] val, input integer budget, input [127:0] tag);
        integer n; begin
            n = 0;
            while (dut.d_reg.q[7:0] !== val) begin
                @(negedge clk); n = n + 1;
                if (n > budget) $fatal(1, "%0s: A never reached %02x (A=%02x PC=%0d uPC=%0d)",
                                       tag, val, dut.d_reg.q[7:0], pc_q, upc);
            end
        end
    endtask

    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("prog: boot done; running real blip.uc ...");

        wait_a(8'h80, 40, "LD A,$80");
        if (cc_q[3] !== 1'b1) $fatal(1, "after LD A,$80: CC.N=%b exp 1", cc_q[3]);
        $display("prog: LD A,$80 executed (A=80, N=1, PC=%0d)", pc_q);

        wait_a(8'h05, 40, "LD A,$05");
        if (cc_q[3] !== 1'b0) $fatal(1, "after LD A,$05: CC.N=%b exp 0", cc_q[3]);
        if (cc_q[2] !== 1'b0) $fatal(1, "after LD A,$05: CC.Z=%b exp 0", cc_q[2]);
        // PC has walked opcode/imm for both instructions: 0->1->2->3->4
        if (pc_q !== 16'd4) $fatal(1, "PC=%0d exp 4 after two LD A,$nn", pc_q);

        $display("PASS - prog: real blip.uc fetch->dispatch->execute->refetch; A=05, PC=4");
        $finish;
    end

    initial begin #400000000; $fatal(1, "TIMEOUT - prog boot never completed"); end
endmodule
`default_nettype wire
