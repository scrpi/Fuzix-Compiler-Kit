// register16 testbench (Icarus -gspecify, TIMED; D-47) — the universal register board.
//
// Exercises the '163-counter superset (cpu-physical-construction.md §6): synchronous clear,
// full-16 and independent per-byte load from Z, off-bus +1 with the carry rippling across
// the byte boundary (the cascade), hold, and the tri-state LEFT driver.
`timescale 1ns/1ps
`default_nettype none
module tb_reg;
    reg         clk = 1'b0;
    always #1000 clk = ~clk;

    reg         reset_n      = 1'b0;
    reg  [15:0] z_in         = 16'h0000;
    reg         load_lo_n    = 1'b1, load_hi_n = 1'b1;
    reg         count_en     = 1'b0;
    reg         drive_left_n = 1'b1;
    wire [15:0] q, left_out;

    register16 dut (
        .clk(clk), .reset_n(reset_n), .z_in(z_in),
        .load_lo_n(load_lo_n), .load_hi_n(load_hi_n), .count_en(count_en),
        .drive_left_n(drive_left_n), .q(q), .left_out(left_out)
    );

    task load16(input [15:0] v);   // FULL16 load from Z
        begin
            @(negedge clk); z_in = v; load_lo_n = 1'b0; load_hi_n = 1'b0;
            @(negedge clk); load_lo_n = 1'b1; load_hi_n = 1'b1;
        end
    endtask

    task tick_count(input integer n);   // n off-bus +1 steps
        integer i;
        begin
            @(negedge clk); count_en = 1'b1;
            for (i = 0; i < n; i = i + 1) @(negedge clk);
            count_en = 1'b0;
        end
    endtask

    initial begin
        // --- synchronous clear -------------------------------------------------------
        @(negedge clk); reset_n = 1'b0;
        @(negedge clk); reset_n = 1'b1;
        if (q !== 16'h0000) $fatal(1, "reset: q=%04x exp 0000", q);

        // --- FULL16 load -------------------------------------------------------------
        load16(16'h1234);
        if (q !== 16'h1234) $fatal(1, "load16: q=%04x exp 1234", q);

        // --- hold (no enables) -------------------------------------------------------
        @(negedge clk); @(negedge clk);
        if (q !== 16'h1234) $fatal(1, "hold: q=%04x exp 1234", q);

        // --- count + carry across the low/high byte boundary -------------------------
        load16(16'h00FF);
        tick_count(1);
        if (q !== 16'h0100) $fatal(1, "cascade: 00FF+1=%04x exp 0100", q);
        tick_count(3);
        if (q !== 16'h0103) $fatal(1, "count: q=%04x exp 0103", q);

        // --- independent per-byte load: change HIGH byte only, low untouched ---------
        @(negedge clk); z_in = 16'hAB00; load_hi_n = 1'b0;   // load high pair only
        @(negedge clk); load_hi_n = 1'b1;
        if (q !== 16'hAB03) $fatal(1, "load-hi-only: q=%04x exp AB03 (low byte must survive)", q);

        // ...and now the LOW byte only ------------------------------------------------
        @(negedge clk); z_in = 16'h0042; load_lo_n = 1'b0;
        @(negedge clk); load_lo_n = 1'b1;
        if (q !== 16'hAB42) $fatal(1, "load-lo-only: q=%04x exp AB42 (high byte must survive)", q);

        // --- LEFT driver: drives Q when enabled, tri-states otherwise ----------------
        @(negedge clk); drive_left_n = 1'b0; #20;
        if (left_out !== 16'hAB42) $fatal(1, "LEFT drive: left_out=%04x exp AB42", left_out);
        @(negedge clk); drive_left_n = 1'b1; #20;
        if (left_out !== 16'hzzzz) $fatal(1, "LEFT tri-state: left_out=%04x exp z", left_out);

        $display("PASS - register16: sync clear, FULL16/per-byte load, off-bus +1 carry, hold, LEFT drive");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "TIMEOUT - register16 bench did not finish");
    end
endmodule
`default_nettype wire
