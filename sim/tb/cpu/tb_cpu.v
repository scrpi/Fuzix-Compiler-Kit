// cpu top-level testbench (Icarus -gspecify, TIMED) — the single entry point.
//
// Powers on the CPU scaffold: the boot loader copies the EEPROM image into the 13
// control-store SRAMs (loading=1), then `loading` drops and the micro-PC walks the
// control store reading real control words (run). This is the boot->run handoff end
// to end. The EEPROM and SRAMs are board-attached here (the boot-write data path is
// board glue, deferred); the handoff logic (mux, /OE, micro-PC, reset) is inside cpu.
//
// Verifies: during run, at micro-PC = k the control store outputs exactly the bytes
// the loader wrote (the image at address k, chip by chip). $fatal on any mismatch.
//
// Build/run via sim/tb/cpu/run.sh (passes -D IMG=...).
`timescale 1ns/1ps
`default_nettype none
module tb_cpu;
    localparam NSEG   = 13;
    localparam SEG_AW = 13;
    localparam DEPTH  = (1 << SEG_AW);
    localparam NCHECK = 16;              // run cycles to verify

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #1000 clk = ~clk;             // ~500 kHz boot clock (slow 555); 2 us period

    wire [16:0]     rom_addr;
    wire [7:0]      rom_data;
    wire [12:0]     cs_addr;
    wire [NSEG-1:0] cs_sel_n;
    wire            cs_oe_n;
    wire [7:0]      cs_wdata;
    wire            loading;
    wire [12:0]     upc;

    cpu dut (
        .clk(clk), .rst_n(rst_n),
        .rom_addr(rom_addr), .rom_data(rom_data),
        .cs_addr(cs_addr), .cs_sel_n(cs_sel_n), .cs_oe_n(cs_oe_n), .cs_wdata(cs_wdata),
        .loading(loading), .upc(upc)
    );

    // Microcode boot EEPROM (board-attached): continuously read.
    sst39sf010a #(.AW(17), .DW(8), .FILE(`IMG), .LOADW(NSEG*DEPTH)) eeprom (
        .a(rom_addr), .dq(rom_data), .ce_n(1'b0), .oe_n(1'b0), .we_n(1'b1)
    );

    // The 13 control-store SRAMs (board-attached). Boot: written from the shared write
    // bus (cs_wdata) under each chip's /WE strobe; run: each drives the control word at
    // cs_addr. (The shared-write-bus / per-chip isolation is board glue here, deferred.)
    wire [7:0] io [0:NSEG-1];
    genvar g;
    generate for (g = 0; g < NSEG; g = g + 1) begin : chip
        wire we_n = cs_sel_n[g] | clk;                  // boot write strobe (board glue)
        assign io[g] = loading ? cs_wdata : 8'bz;       // boot write data (board glue)
        is61c64 #(.AW(SEG_AW), .DW(8)) u (
            .a(cs_addr), .io(io[g]), .ce_n(1'b0), .oe_n(cs_oe_n), .we_n(we_n)
        );
    end endgenerate

    integer n, k;
    reg [7:0] expb;
    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;                                   // release boot reset

        wait (loading == 1'b0);                         // boot copy complete
        $display("cpu: boot done; micro-PC now walking the control store ...");

        for (n = 0; n < NCHECK; n = n + 1) begin
            @(negedge clk);                             // mid-cycle: control word settled
            if (upc !== n[12:0])
                $fatal(1, "micro-PC = %0d, expected %0d", upc, n);
            for (k = 0; k < NSEG; k = k + 1) begin
                expb = eeprom.mem[k*DEPTH + upc];
                if (io[k] !== expb)
                    $fatal(1, "run read mismatch: chip %0d uPC %0d got %02x exp %02x",
                           k, upc, io[k], expb);
            end
        end

        $display("PASS - booted, then read %0d control words via the micro-PC (vs the image)",
                 NCHECK);
        $finish;
    end

    initial begin
        #300000000;                                     // > boot time (106k x 2 us ~= 213 ms)
        $fatal(1, "TIMEOUT - boot never completed");
    end
endmodule
`default_nettype wire
