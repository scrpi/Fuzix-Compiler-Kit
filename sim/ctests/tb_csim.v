// tb_csim.v — run a COMPILED C PROGRAM on the gate-level BLIP CPU (Icarus -gspecify, TIMED; D-47).
//
// This is the bridge from the C toolchain (tools/fcc) to the structural CPU. The CPU boots its
// microcode from FILE (the WCS image) exactly as the other end-to-end benches do, then runs the
// program out of a 64 KB behavioural memory with NO debug injection (ir_inject=0, cond_inject=0).
//
// The program image is the RAW flat binary emitted by `ldblip -b -C0` (linked at base 0, entered
// at PC=0), converted to one-hex-byte-per-line and $readmemh'd into mem[] at index 0. crt0 sets
// SP=$FEFF and JSRs _main.
//
// OUTPUT / EXIT — the testbench memory model decodes the same magic I/O page the C runtime
// (crt0 / libblip) and the emublip software emulator use, so the SAME image runs on both:
//   0xFF00  latch the low byte of a 16-bit int to print
//   0xFF01  print signed 16-bit ((hi<<8)|lo) as a decimal line   (write the hi byte here)
//   0xFF02  putchar (write the byte)
//   0xFF03  exit(low byte)  -> end of program
// Program stdout is written verbatim to the +OUT file (so it can be diffed byte-for-byte against
// emublip's stdout); the exit status is printed to the sim log as "[EXIT] <n>".
//
// Plusargs:  +PROG=<hexfile>  (required) the program image;  +OUT=<file> (required) program stdout.
`timescale 1ns/1ps
`default_nettype none
module tb_csim;
    reg clk = 1'b0, rst_n = 1'b0;
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
        .clk(clk), .rst_n(rst_n), .ir_inject(1'b0), .ir_drive(8'h00),
        .cond_inject(1'b0), .cond_drive(16'h0000),
        .irq(1'b0), .nmi(1'b0), .wait_ready(1'b1),
        .busreq_n(1'b1), .busgrant_n(busgrant_n),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n),
        .loading(loading), .upc(upc), .cw(cw), .lut_out(lut_out), .ir_q(ir_q),
        .pc_q(pc_q), .z_q(z_q), .cc_q(cc_q)
    );

    // 64 KB behavioural memory; the CPU drives D during /RD. (Reset identity-maps logical->physical,
    // so the program's flat 0-based image sits at a[15:0].)
    reg [7:0] mem [0:65535];
    assign d = (rd_n === 1'b0) ? mem[a[15:0]] : 8'bz;

    integer fd;
    reg [7:0]        io_lo;             // 0xFF00 latch
    reg signed [15:0] pv;
    reg [4095:0] progfile, outfile;
    integer i;

    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
        if (!$value$plusargs("PROG=%s", progfile)) begin
            $display("[ERROR] tb_csim: no +PROG=<hexfile> given"); $finish;
        end
        $readmemh(progfile, mem);
        if (!$value$plusargs("OUT=%s", outfile)) begin
            $display("[ERROR] tb_csim: no +OUT=<file> given"); $finish;
        end
        fd = $fopen(outfile, "w");
        if (fd == 0) begin $display("[ERROR] tb_csim: cannot open +OUT file"); $finish; end
    end

    // A device captures a write on /WR's rising edge (interface.md §4.2). Decode the I/O page there;
    // every other write lands in RAM.
    always @(posedge wr_n) begin
        if (!$isunknown({a[15:0], d})) begin
            case (a[15:0])
                16'hFF00: io_lo <= d;                                   // latch int low byte
                16'hFF01: begin pv = {d, io_lo}; $fwrite(fd, "%0d\n", pv); end  // print signed int
                16'hFF02: $fwrite(fd, "%c", d);                         // putchar
                16'hFF03: begin                                         // exit(low byte) — done
                    $fclose(fd);
                    $display("[EXIT] %0d", d);
                    $finish;
                end
                default:  mem[a[15:0]] <= d;
            endcase
        end
    end

    // boot the microcode, then the program runs from the reset vector (PC=0 = crt0)
    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;
        wait (loading == 1'b0);
        $display("[CSIM] boot done; running program ...");
    end

    // wall-clock backstop: a real-program hang must not run forever
    initial begin
        #2000000000;   // 1,000,000 clocks
        $fclose(fd);
        $display("[TIMEOUT] program never hit the exit port (PC=%0d uPC=%0d ir=%02x)", pc_q, upc, ir_q);
        $finish;
    end
endmodule
`default_nettype wire
