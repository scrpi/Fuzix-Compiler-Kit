// memory_interface testbench (Icarus -gspecify, TIMED; D-47) — the MDR + external bus port.
//
// Exercises the read/write path the way the microcode will drive it (hardware.md §2,
// interface.md §4): stage a byte into MDR from Z, WRITE it to memory, then READ it back and
// confirm MDR captured the device's byte. The memory is a BEHAVIOURAL model living in the
// harness, outside the CPU under test (R-SIM-3): it drives D[7:0] while /RD is low and
// captures D on the rising edge of /WR (interface.md §4.1/§4.2).
//
// What it checks at each step:
//   * /RD//WR are framed correctly off MEM_OP, and the CPU drives D ONLY during a write;
//   * the physical address is the reset identity map of MAR (A = {8'h00, MAR});
//   * a Z_DEST=MDR load stages the write byte; WRITE lands it at MAR in memory;
//   * a READ captures the device's byte into MDR on the terminating edge (a fresh value,
//     proving the read path rather than a stale MDR);
//   * LEFT_SRC=MDR drives MDR onto the LEFT low lane, and tri-states it otherwise.
`timescale 1ns/1ps
`default_nettype none
module tb_mem;
    reg         clk = 1'b0;
    always #1000 clk = ~clk;                 // 2 us period (matches the cpu bench boot clock)

    // --- decoded control lines into the DUT (active LOW, as the decoder emits them) ----
    // MEM_OP one-hot ~(1<<op): IDLE=1110, READ=1101, WRITE=1011.
    localparam [3:0] OP_IDLE = 4'b1110, OP_READ = 4'b1101, OP_WRITE = 4'b1011;
    reg  [3:0]  mem_op_n       = OP_IDLE;
    reg         z_dest_mdr_n   = 1'b1;       // 0 = capture Z-low into MDR
    reg         left_src_mdr_n = 1'b1;       // 0 = drive MDR onto LEFT
    reg  [15:0] mar            = 16'h0000;
    reg  [7:0]  z_lo           = 8'h00;

    wire [7:0]  mdr_q, left_lo;
    wire [23:0] a;
    wire [7:0]  d;
    wire        rd_n, wr_n;

    memory_interface dut (
        .clk(clk), .mem_op_n(mem_op_n), .z_dest_mdr_n(z_dest_mdr_n), .left_src_mdr_n(left_src_mdr_n),
        .mar(mar), .z_lo(z_lo), .mdr_q(mdr_q), .left_lo(left_lo),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n)
    );

    // --- behavioural memory model (the harness, outside the DUT — R-SIM-3) -------------
    reg [7:0] mem [0:65535];
    assign d = (rd_n === 1'b0) ? mem[a[15:0]] : 8'bz;   // device drives D while /RD low
    always @(posedge wr_n) mem[a[15:0]] <= d;           // capture on the /WR rising edge (§4.2)

    // --- directed driver: one byte lane through the full write/read round trip ---------
    // Each step changes inputs at negedge (stable before the posedge), acting one cycle later.
    task stage_mdr(input [7:0] val);        // Z_DEST=MDR: capture Z-low into MDR (no bus cycle)
        begin
            @(negedge clk); z_lo = val; z_dest_mdr_n = 1'b0; mem_op_n = OP_IDLE;
            @(negedge clk); z_dest_mdr_n = 1'b1;            // captured on the intervening posedge
        end
    endtask

    task wr_mem(input [15:0] addr);         // WRITE: MDR -> D, device captures on /WR rising
        begin
            @(negedge clk); mar = addr; mem_op_n = OP_WRITE; #50;   // settle strobes + '541 enable
            if (wr_n !== 1'b0) $fatal(1, "WRITE: /WR not asserted (wr_n=%b)", wr_n);
            if (a !== {8'h00, addr}) $fatal(1, "WRITE: A=%06x exp %06x", a, {8'h00, addr});
            if (d !== mdr_q) $fatal(1, "WRITE: CPU not driving D with MDR (D=%02x MDR=%02x)", d, mdr_q);
            @(negedge clk); mem_op_n = OP_IDLE;             // /WR rises here -> device captures
            @(negedge clk);
        end
    endtask

    task rd_mem(input [15:0] addr);         // READ: device drives D, MDR captures on terminating edge
        begin
            @(negedge clk); mar = addr; mem_op_n = OP_READ; #50;    // settle strobes + device drive
            if (rd_n !== 1'b0) $fatal(1, "READ: /RD not asserted (rd_n=%b)", rd_n);
            if (wr_n !== 1'b1) $fatal(1, "READ: /WR asserted during a read (wr_n=%b)", wr_n);
            @(negedge clk); mem_op_n = OP_IDLE;             // MDR captured on the intervening posedge
        end
    endtask

    initial begin
        // --- WRITE A5 -> 1234, via a Z_DEST=MDR stage then a WRITE bus cycle ------------
        stage_mdr(8'hA5);
        if (mdr_q !== 8'hA5) $fatal(1, "stage: MDR=%02x exp A5", mdr_q);
        if (d   !== 8'hzz)   $fatal(1, "idle: CPU drove D off a bus cycle (D=%02x)", d);
        wr_mem(16'h1234);
        if (mem[16'h1234] !== 8'hA5) $fatal(1, "WRITE: mem[1234]=%02x exp A5", mem[16'h1234]);

        // --- clobber MDR via a second store, so the read-back proves the read path ------
        stage_mdr(8'h3C);
        wr_mem(16'h1235);
        if (mdr_q !== 8'h3C) $fatal(1, "MDR should hold 3C before read-back (got %02x)", mdr_q);

        // --- READ 1234 -> MDR must become A5 (the device's byte, not the stale 3C) ------
        rd_mem(16'h1234);
        if (mdr_q !== 8'hA5) $fatal(1, "READ-back: MDR=%02x exp A5", mdr_q);

        // --- LEFT_SRC=MDR drives the read byte onto LEFT; tri-states otherwise ----------
        @(negedge clk); left_src_mdr_n = 1'b0; #20;
        if (left_lo !== 8'hA5) $fatal(1, "LEFT_SRC=MDR: LEFT=%02x exp A5", left_lo);
        @(negedge clk); left_src_mdr_n = 1'b1; #20;
        if (left_lo !== 8'hzz) $fatal(1, "LEFT_SRC off: LEFT=%02x exp z", left_lo);

        $display("PASS - memory_interface: stage/WRITE/READ round trip, /RD//WR framing, A=identity(MAR), LEFT drive");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "TIMEOUT - memory_interface bench did not finish");
    end
endmodule
`default_nettype wire
