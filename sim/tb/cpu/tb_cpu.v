// cpu top-level testbench (Icarus -gspecify, TIMED) — the single entry point.
//
// Pure harness now: it supplies the clock, the power-on reset, and the checks. The CPU
// is self-contained (its own boot EEPROM and control store live inside `cpu`), so this
// bench instantiates `cpu` and watches it boot and run — no board-attached memory here.
//
// Power-on -> the loader copies the EEPROM image into the control store (loading=1) ->
// `loading` drops -> the micro-PC walks the control store, and `cw` exposes the bytes it
// reads. Verifies cw against the burned image (the EEPROM's contents, read hierarchically)
// at each micro-PC step. $fatal on any mismatch.
//
// Build/run via sim/tb/cpu/run.sh (passes -D IMG=...).
`timescale 1ns/1ps
`default_nettype none
module tb_cpu;
    localparam NSEG   = 13;
    localparam DEPTH  = 8192;
    localparam NCHECK = 16;              // run cycles to verify

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #1000 clk = ~clk;             // ~500 kHz boot clock (slow 555); 2 us period

    wire         loading;
    wire [12:0]  upc;
    wire [103:0] cw;

    cpu #(.FILE(`IMG)) dut (
        .clk(clk), .rst_n(rst_n),
        .loading(loading), .upc(upc), .cw(cw)
    );

    integer n, k;
    reg [7:0] expb, gotb;
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
                expb = dut.eeprom.mem[k*DEPTH + upc];   // the burned image, chip-major
                gotb = cw[8*k +: 8];
                if (gotb !== expb)
                    $fatal(1, "run read mismatch: chip %0d uPC %0d got %02x exp %02x",
                           k, upc, gotb, expb);
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
