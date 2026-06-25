// right_bus testbench (Icarus -gspecify, TIMED; D-47) — the ALU RIGHT source bus.
//
// Combinational: select each RIGHT_SRC in turn and check the bus carries SCR1, SCR2, or the
// constant-generator value {-2,-1,0,+1,+2}. Also checks the bus floats when nothing is
// selected (no source drives — the one-hot is fully inactive).
`timescale 1ns/1ps
`default_nettype none
module tb_right;
    // RIGHT_SRC encodings
    localparam SCR1=0, SCR2=1, M2=2, M1=3, ZERO=4, P1=5, P2=6;

    reg  [15:0] scr1, scr2;
    reg  [7:0]  src_n = 8'hFF;          // one-hot, active low (FF = nothing selected)
    wire [15:0] right;

    right_bus dut (.scr1(scr1), .scr2(scr2), .right_src_n(src_n), .right(right));

    integer errors = 0;
    task chk(input [3:0] sel, input [15:0] exp);
        begin
            src_n = ~(8'd1 << sel); #60;
            if (right !== exp) begin $display("FAIL sel%0d: RIGHT=%04x exp %04x", sel, right, exp); errors=errors+1; end
        end
    endtask

    initial begin
        scr1 = 16'hCAFE; scr2 = 16'h1234;
        chk(SCR1, 16'hCAFE);
        chk(SCR2, 16'h1234);
        chk(M2,   16'hFFFE);            // -2
        chk(M1,   16'hFFFF);            // -1
        chk(ZERO, 16'h0000);            //  0
        chk(P1,   16'h0001);            // +1
        chk(P2,   16'h0002);            // +2
        // a different scratch value still flows through
        scr1 = 16'hBEEF; chk(SCR1, 16'hBEEF);
        // nothing selected -> the bus floats
        src_n = 8'hFF; #60;
        if (right !== 16'hzzzz) begin $display("FAIL idle: RIGHT=%04x exp z", right); errors=errors+1; end

        if (errors == 0)
            $display("PASS - right_bus: SCR1/SCR2 + const-gen {-2,-1,0,+1,+2}, idle floats");
        else
            $fatal(1, "right_bus: %0d check(s) FAILED", errors);
        $finish;
    end

    initial begin #1000000; $fatal(1, "TIMEOUT - right_bus bench"); end
endmodule
`default_nettype wire
