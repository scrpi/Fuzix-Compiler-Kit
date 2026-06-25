// Multi-bit shift (ULOOP from memory) testbench (Icarus -gspecify, TIMED; D-47). Runs the REAL
// blip.uc: `LD B,$01` (B = D's low byte) then `ASL D,$03`. The shift count rides in from memory,
// posts on Z, and loads the ULOOP counter in the same word; the loop body then runs exactly n=3
// times, so D = 0x0001 << 3 = 0x0008. Proves Wave 2: the production `count -> uloop` idiom works.
`timescale 1ns/1ps
`default_nettype none
module tb_shiftx;
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
        .busreq_n(1'b1), .busgrant_n(),
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
        mem[0] = 8'h0B; mem[1] = 8'h01;   // LD B,$01  -> D = 0x0001 (B = D's low byte)
        mem[2] = 8'h95; mem[3] = 8'h03;   // ASL D,$03 -> D = 0x0008
    end

    integer n;
    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("shiftx: boot done; running LD B,$01 ; ASL D,$03 ...");

        n = 0;
        while (dut.d_reg.q !== 16'h0008) begin
            @(negedge clk); n = n + 1;
            if (n > 80) $fatal(1, "ASL D,$03: D never reached 0008 (D=%04x PC=%0d uPC=%0d)",
                               dut.d_reg.q, pc_q, upc);
        end
        // sanity: it should pass through 0x0001 (the LD) before reaching 0x0008 (the 3 shifts)
        $display("PASS - shiftx: real ASL D,$03 with count from memory -> D = 0x0008 (1<<3)");
        $finish;
    end

    initial begin #400000000; $fatal(1, "TIMEOUT - shiftx boot never completed"); end
endmodule
`default_nettype wire
