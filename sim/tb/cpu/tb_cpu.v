// cpu top-level testbench (Icarus -gspecify, TIMED) — the microsequencer walk.
//
// The CPU is self-contained (its own boot EEPROM + control store), so this bench supplies
// the clock, the power-on reset, the injected opcode (ir_drive) and condition lines
// (cond_drive — the datapath that would drive them does not exist yet), and the checks.
//
// It loads a DIRECTED control-store image (sim/tb/cpu/mk_seq_image.py) chosen to drive a
// known µPC walk through the fetch/branch core of USEQ_OP, then verifies, at each step:
//   * the µPC takes the expected next value (INC / JUMP / BRANCH taken+not / DISPATCH_IR);
//   * the control word read at that µPC matches the burned image (the WCS read path);
//   * the control-word decoder is the correct one-hot of the live word (one field/width);
// and that DISPATCH_IR lands on the opcode-LUT target and WAIT holds the µPC.
//
// The boot copy itself is exercised here too: power-on streams the directed image through
// the real loader + its onboard EEPROM into the WCS, and the per-µPC WCS check above
// re-reads it. The copy is image-independent address-slicing, so this run on the standard
// path is the loader's proof — no separate loader bench is needed (toolchain.md §3.5).
// Build/run via sim/tb/cpu/run.sh (passes -D IMG=... = the directed image).
`timescale 1ns/1ps
`default_nettype none
module tb_cpu;
    localparam NWCS  = 11;               // 11 WCS SRAMs hold the 88-bit control word
    localparam DEPTH = 4096;
    localparam IR_OPCODE = 8'h42;        // injected opcode (matches mk_seq_image.py)

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #1000 clk = ~clk;             // ~500 kHz boot clock (slow 555); 2 us period

    // Debug-tap drives: the opcode into IR, and the condition lines. cond_drive sets
    // C (idx 1) and IRQ_PENDING (idx 9) HIGH, Z (idx 0) LOW; TRUE (idx 7) is internal.
    reg  [7:0]  ir_drive   = IR_OPCODE;
    reg  [15:0] cond_drive = 16'h0202;

    wire        loading;
    wire [11:0] upc;
    wire [87:0] cw;
    wire [11:0] lut_out;

    // ir_inject=1: this bench injects the opcode via ir_drive (it tests the microsequencer
    // walk, not a memory fetch); the system-bus ports float (no memory model attached).
    cpu #(.FILE(`IMG)) dut (
        .clk(clk), .rst_n(rst_n), .ir_inject(1'b1), .ir_drive(ir_drive),
        .cond_inject(1'b1), .cond_drive(cond_drive),
        .irq(1'b0), .nmi(1'b0), .wait_ready(1'b1),
        .busreq_n(1'b1), .busgrant_n(),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out)
    );

    // pass 1: the µPC walk after boot, ending in RETURN_FETCH -> 0 (see mk_seq_image.py)
    localparam NSTEP = 10;
    reg [11:0] want [0:NSTEP-1];
    initial begin
        want[0]=12'd0;  want[1]=12'd3;  want[2]=12'd4;  want[3]=12'd6;  want[4]=12'd8;
        want[5]=12'd9;  want[6]=12'd10; want[7]=12'd16; want[8]=12'd17; want[9]=12'd0;
    end

    integer s;
    reg [7:0] expb, gotb;
    task check_word;                                   // WCS read path + decoder at this µPC
        integer kk;
        begin
            for (kk = 0; kk < NWCS; kk = kk + 1) begin
                expb = dut.loader.eeprom.mem[kk*DEPTH + upc];
                gotb = cw[8*kk +: 8];
                if (gotb !== expb)
                    $fatal(1, "µPC %0d: WCS chip %0d got %02x exp %02x", upc, kk, gotb, expb);
            end
            if (dut.dec.left_src_n  !== ~(16'd1 << cw[29:26]))
                $fatal(1, "decoder LEFT_SRC @µPC %0d", upc);
            if (dut.dec.right_src_n !== ~(8'd1  << cw[34:32]))
                $fatal(1, "decoder RIGHT_SRC @µPC %0d", upc);
            if (dut.dec.mem_op_n    !== ~(4'd1  << cw[73:72]))
                $fatal(1, "decoder MEM_OP @µPC %0d", upc);
        end
    endtask
    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;                                   // release boot reset

        wait (loading == 1'b0);                         // boot copy complete; µPC released at 0
        $display("cpu: boot done; verifying the microsequencer walk ...");

        // pass 1: INC / JUMP / BRANCH(taken+not, both groups, polarity) / DISPATCH_IR,
        // ending with RETURN_FETCH back to the fetch entry (0).
        for (s = 0; s < NSTEP; s = s + 1) begin
            @(negedge clk);                             // mid-cycle: word + next-µPC settled
            if (upc !== want[s])
                $fatal(1, "pass1 step %0d: micro-PC = %0d, expected %0d", s, upc, want[s]);
            check_word;
            if (upc === 12'd10 && lut_out !== 12'd16)   // DISPATCH_IR target
                $fatal(1, "DISPATCH_IR: lut_out = %0d, expected 16 (IR=%02x)", lut_out, IR_OPCODE);
        end

        // pass 2: now raise Z. The SAME BRANCH at µPC 3 (UCOND_SEL=Z) now takes -> 99=WAIT,
        // proving the condition mux reads the line and WAIT holds. (µPC is back at 0 here.)
        cond_drive = cond_drive | 16'h0001;             // Z (idx 0) = 1
        @(negedge clk);  if (upc !== 12'd3)  $fatal(1, "pass2: µPC = %0d, expected 3", upc);
        @(negedge clk);  if (upc !== 12'd99) $fatal(1, "pass2: BRANCH Z (now 1) did not take to 99 (got %0d)", upc);
        @(negedge clk);  if (upc !== 12'd99) $fatal(1, "WAIT did not hold the micro-PC at 99 (got %0d)", upc);

        $display("PASS - microsequencer: INC/JUMP/BRANCH(+/-cond, both groups, polarity)/DISPATCH_IR/RETURN_FETCH/WAIT");
        $finish;
    end

    initial begin
        #300000000;                                     // > boot time (53k x 2 us ~= 106 ms)
        $fatal(1, "TIMEOUT - boot never completed");
    end
endmodule
`default_nettype wire
