// byte-lane steer unit testbench (Icarus -gspecify, TIMED; D-47) — left_lane + z_lane.
//
// Exhaustively drives the two combinational steer blocks and checks every mode:
//   LEFT_LANE  FULL16 / LOW(zero-ext) / SIGN_EXT / HIGH_TO_LOW — with both a set and a clear
//              low-byte MSB, so zero-extend and sign-extend are distinguished.
//   Z_LANE     FULL16 / LOW / HIGH — the steered z_load (high-byte promote on HIGH) and the two
//              active-HIGH lane blockers.
`timescale 1ns/1ps
`default_nettype none
module tb_lane;
    // one-hot active-low from a 2-bit field code (the decoder's '139 convention)
    function [3:0] oh4(input [1:0] v); oh4 = ~(4'd1 << v); endfunction
    localparam [1:0] L_FULL16=0, L_LOW=1, L_SX=2, L_H2L=3;   // LEFT_LANE codes
    localparam [1:0] Z_FULL16=0, Z_LOW=1, Z_HIGH=2;          // Z_LANE codes

    // --- left_lane: raw LEFT -> steered ALU operand ---------------------------
    reg  [15:0] lraw;
    reg  [3:0]  llane_n;
    wire [15:0] left;
    left_lane u_left (.left_raw(lraw), .left_lane_n(llane_n), .left(left));

    // --- z_lane: Z -> steered load bus + lane blockers ------------------------
    reg  [15:0] zin;
    reg  [3:0]  zlane_n;
    wire [15:0] zload;
    wire        blo, bhi;
    z_lane u_z (.z(zin), .z_lane_n(zlane_n), .z_load(zload), .block_lo(blo), .block_hi(bhi));

    // Settle past the 2-level high-lane '157 chain (sel->sx->mux_full, ~22 ns) before sampling.
    integer errors = 0;
    task ckl(input [15:0] exp, input [255:0] m);
        begin #80; if (left !== exp) begin
            $display("FAIL %0s: left=%04x exp %04x", m, left, exp); errors=errors+1; end end
    endtask
    task ckz(input [15:0] exp, input eblo, input ebhi, input [255:0] m);
        begin #80;
            if (zload !== exp) begin $display("FAIL %0s: z_load=%04x exp %04x", m, zload, exp); errors=errors+1; end
            if (blo !== eblo)  begin $display("FAIL %0s: block_lo=%b exp %b", m, blo, eblo); errors=errors+1; end
            if (bhi !== ebhi)  begin $display("FAIL %0s: block_hi=%b exp %b", m, bhi, ebhi); errors=errors+1; end
        end
    endtask

    initial begin
        // ===== LEFT_LANE — low byte 0xFF (MSB set): zero-ext != sign-ext ======
        lraw = 16'h12FF;
        llane_n = oh4(L_FULL16); ckl(16'h12FF, "LEFT FULL16");
        llane_n = oh4(L_LOW);    ckl(16'h00FF, "LEFT LOW (zero-ext)");
        llane_n = oh4(L_SX);     ckl(16'hFFFF, "LEFT SIGN_EXT (msb=1)");
        llane_n = oh4(L_H2L);    ckl(16'h0012, "LEFT HIGH_TO_LOW");
        // ===== LEFT_LANE — low byte 0x7E (MSB clear): sign-ext zero-fills =====
        lraw = 16'hAB7E;
        llane_n = oh4(L_FULL16); ckl(16'hAB7E, "LEFT FULL16 (2)");
        llane_n = oh4(L_LOW);    ckl(16'h007E, "LEFT LOW (msb=0)");
        llane_n = oh4(L_SX);     ckl(16'h007E, "LEFT SIGN_EXT (msb=0 == zero-ext)");
        llane_n = oh4(L_H2L);    ckl(16'h00AB, "LEFT HIGH_TO_LOW (hi=AB)");

        // ===== Z_LANE — z = 0x34D6 ============================================
        zin = 16'h34D6;
        zlane_n = oh4(Z_FULL16); ckz(16'h34D6, 1'b0, 1'b0, "Z FULL16 (both load, hi=z[15:8])");
        zlane_n = oh4(Z_LOW);    ckz(16'h34D6, 1'b0, 1'b1, "Z LOW (block hi)");
        zlane_n = oh4(Z_HIGH);   ckz(16'hD6D6, 1'b1, 1'b0, "Z HIGH (promote z[7:0], block lo)");

        if (errors == 0)
            $display("PASS - lane: LEFT FULL16/LOW/SIGN_EXT/HIGH_TO_LOW + Z FULL16/LOW/HIGH (promote+blockers)");
        else
            $fatal(1, "lane: %0d check(s) FAILED", errors);
        $finish;
    end

    initial begin #100000; $fatal(1, "TIMEOUT - lane bench"); end
endmodule
`default_nettype wire
