// cc testbench (Icarus -gspecify, TIMED; D-47) — the condition-code board.
//
// Clocks the CC register through its write paths and checks the latched value and the derived
// branch conditions: reset state, per-flag ALU writes under FLAG_WE, V_SRC/C_SRC overrides,
// Z_ACCUM, the seven CC conditions, WHOLE_Z / AND / OR writes, and the M/I privilege interlock.
`timescale 1ns/1ps
`default_nettype none
module tb_cc;
    // decoded one-hot active-low helpers
    function [3:0] oh4(input [1:0] v); oh4 = ~(4'd1 << v); endfunction
    // V_SRC/C_SRC: FROM_ALU=0 FORCE_0=1 FORCE_1=2 ; CC_WRITE: ALU=0 WHOLE_Z=1 AND=2 OR=3
    // CC_MI: HOLD=0 SET_ON_ENTRY=1 SET_I=2 CLR_I=3
    localparam [4:0] WE_H=5'b00001, WE_N=5'b00010, WE_Z=5'b00100, WE_V=5'b01000, WE_C=5'b10000;

    reg clk = 1'b0; always #500 clk = ~clk;
    reg reset_n = 1'b0;
    reg fn=0, fz=0, fv=0, fc=0, fh=0;
    reg [4:0] flag_we = 5'b0;
    reg [3:0] v_src_n = 4'hE, c_src_n = 4'hE;   // FROM_ALU
    reg z_accum = 1'b0;
    reg [3:0] cc_write_n = 4'hE;                 // ALU_FLAGS
    reg [3:0] cc_mi_n = 4'hE;                    // HOLD
    reg [7:0] z_lo = 8'h0;
    wire [7:0] cc_q; wire cc_m; wire [6:0] cond;

    cc dut (
        .clk(clk), .reset_n(reset_n),
        .flag_n(fn), .flag_z(fz), .flag_v(fv), .flag_c(fc), .flag_h(fh),
        .flag_we(flag_we), .v_src_n(v_src_n), .c_src_n(c_src_n), .z_accum(z_accum),
        .cc_write_n(cc_write_n), .cc_mi_n(cc_mi_n), .z_lo(z_lo), .hold(1'b0),
        .cc_q(cc_q), .cc_m(cc_m), .cond(cond)
    );

    integer errors = 0;
    task tick; begin @(posedge clk); #80; end endtask
    task chk(input [7:0] exp, input [127:0] msg);
        begin if (cc_q !== exp) begin $display("FAIL %0s: CC=%02x exp %02x", msg, cc_q, exp); errors=errors+1; end end
    endtask
    task chkc(input integer i, input val, input [127:0] msg);
        begin if (cond[i] !== val) begin $display("FAIL %0s: cond[%0d]=%b exp %b", msg, i, cond[i], val); errors=errors+1; end end
    endtask

    // reset between phases of "all defaults" — set the hold/NOP control
    task nop_ctrl; begin
        flag_we=5'b0; v_src_n=4'hE; c_src_n=4'hE; z_accum=0; cc_write_n=4'hE; cc_mi_n=4'hE; z_lo=8'h0;
    end endtask

    initial begin
        // ---- reset: CC <- 0x90 (M=1, I=1, flags 0) --------------------------------
        nop_ctrl; reset_n=1'b0; tick;
        chk(8'h90, "reset");
        reset_n=1'b1;

        // ---- ALU write N,Z (FLAG_WE selects); others hold -------------------------
        nop_ctrl; fn=1; fz=1; fv=0; fc=0; flag_we=WE_N|WE_Z; tick;
        chk(8'h9C, "write N,Z");           // M1 I1 N1 Z1
        chkc(0, 1, "Z cond"); chkc(2, 1, "N cond");
        // a hold cycle keeps them
        nop_ctrl; tick; chk(8'h9C, "hold");

        // ---- ALU write C (only C); N,Z still held ---------------------------------
        nop_ctrl; fc=1; flag_we=WE_C; tick;
        chk(8'h9D, "write C");
        chkc(1, 1, "C cond"); chkc(4, 1, "C_OR_Z cond");

        // ---- V_SRC=FORCE_1 writes V=1 regardless of flag_v ------------------------
        nop_ctrl; fv=0; v_src_n=oh4(2); flag_we=WE_V; tick;
        chk(8'h9F, "V forced 1");          // now N1 Z1 V1 C1
        chkc(3, 1, "V cond"); chkc(5, 0, "N_XOR_V");   // N(1)^V(1)=0
        chkc(6, 1, "Z_OR_NXORV");          // Z(1) | 0 = 1

        // ---- C_SRC=FORCE_0 clears C -----------------------------------------------
        nop_ctrl; c_src_n=oh4(1); flag_we=WE_C; tick;
        chk(8'h9E, "C forced 0");
        chkc(1, 0, "C cond");

        // ---- Z_ACCUM: AND new Z with prior Z. First force Z=0, then accum a 1 -----
        nop_ctrl; fz=0; flag_we=WE_Z; tick;          // Z <- 0
        chk(8'h9A, "Z=0");
        nop_ctrl; fz=1; z_accum=1; flag_we=WE_Z; tick;   // af_z = 1 & oldZ(0) = 0
        chk(8'h9A, "Z_ACCUM keeps 0");

        // ---- ALU write H (half-carry): H loads, and a non-H write must not clear it
        nop_ctrl; fh=1; flag_we=WE_H; tick;
        if (cc_q[5] !== 1'b1) begin $display("FAIL write H: H=%b exp 1", cc_q[5]); errors=errors+1; end
        nop_ctrl; fn=1'b0; flag_we=WE_N; tick;
        if (cc_q[5] !== 1'b1) begin $display("FAIL H hold: H=%b exp 1 (a WE_N write cleared H)", cc_q[5]); errors=errors+1; end

        // ---- WHOLE_Z: load the WHOLE byte from Z (RTI/PULS CC) — M/I too, priv-gated.
        // In supervisor, M/I track the byte; here the byte carries M=1,I=1 so they stay set.
        nop_ctrl; cc_write_n=oh4(1); z_lo=8'hBE; tick;   // M1 .6 H1 I1 N1 Z1 V1 C0
        chk(8'hBE, "WHOLE_Z");             // M1 H1 I1 N1 Z1 V1 C0 = 1011_1110
        // ---- AND_MASK: clear V via mask -------------------------------------------
        nop_ctrl; cc_write_n=oh4(2); z_lo=8'hFD; tick;   // mask clears bit1 (V)
        chk(8'hBC, "AND_MASK");
        // ---- OR_MASK: set C via mask ----------------------------------------------
        nop_ctrl; cc_write_n=oh4(3); z_lo=8'h01; tick;
        chk(8'hBD, "OR_MASK");

        // ---- CC_MI_LOAD: SET_ON_ENTRY forces M=1,I=1 (entry bypasses privilege) ----
        nop_ctrl; cc_mi_n=oh4(1); tick;
        if (cc_q[7] !== 1'b1 || cc_q[4] !== 1'b1) begin $display("FAIL SET_ON_ENTRY: M=%b I=%b exp 1,1", cc_q[7], cc_q[4]); errors=errors+1; end

        // ---- SEI/CLI: SET_I/CLR_I change I ALONE, M held (in supervisor) -----------
        nop_ctrl; cc_mi_n=oh4(3); tick;                      // CLR_I: I<-0, M held
        if (cc_q[4] !== 1'b0 || cc_q[7] !== 1'b1) begin $display("FAIL CLR_I: M=%b I=%b exp 1,0", cc_q[7], cc_q[4]); errors=errors+1; end
        nop_ctrl; cc_mi_n=oh4(2); tick;                      // SET_I: I<-1, M held
        if (cc_q[4] !== 1'b1 || cc_q[7] !== 1'b1) begin $display("FAIL SET_I: M=%b I=%b exp 1,1", cc_q[7], cc_q[4]); errors=errors+1; end

        // ---- ANDCC/ORCC mask M/I in supervisor; M held while I moves --------------
        nop_ctrl; cc_write_n=oh4(2); z_lo=8'hEF; tick;       // CC <- CC & 0xEF  -> clear I, M held
        if (cc_q[4] !== 1'b0 || cc_q[7] !== 1'b1) begin $display("FAIL AND_MASK I: M=%b I=%b exp 1,0", cc_q[7], cc_q[4]); errors=errors+1; end
        nop_ctrl; cc_write_n=oh4(3); z_lo=8'h10; tick;       // CC <- CC | 0x10  -> set I, M held
        if (cc_q[4] !== 1'b1 || cc_q[7] !== 1'b1) begin $display("FAIL OR_MASK I: M=%b I=%b exp 1,1", cc_q[7], cc_q[4]); errors=errors+1; end

        // ---- WHOLE_Z (RTI/PULS CC) restores M and I independently from the stack byte
        nop_ctrl; cc_write_n=oh4(1); z_lo=8'h80; tick;       // CC <- whole(0x80): M<-1, I<-0
        if (cc_q[7] !== 1'b1 || cc_q[4] !== 1'b0) begin $display("FAIL WHOLE_Z M/I indep: M=%b I=%b exp 1,0", cc_q[7], cc_q[4]); errors=errors+1; end
        nop_ctrl; cc_write_n=oh4(1); z_lo=8'h00; tick;       // CC <- whole(0x00): M<-0 (drop to user), I<-0
        if (cc_q[7] !== 1'b0 || cc_q[4] !== 1'b0) begin $display("FAIL WHOLE_Z M/I clear: M=%b I=%b exp 0,0", cc_q[7], cc_q[4]); errors=errors+1; end

        // ---- privilege: now in USER (M=0). M/I writes are IGNORED; low flags still load.
        nop_ctrl; cc_write_n=oh4(1); z_lo=8'hFF; tick;       // WHOLE_Z tries M=1,I=1 -> held; H/N/Z/V/C load
        if (cc_q[7] !== 1'b0 || cc_q[4] !== 1'b0) begin $display("FAIL priv WHOLE_Z: user changed M/I to %b,%b (must stay 0)", cc_q[7], cc_q[4]); errors=errors+1; end
        if (cc_q[3] !== 1'b1) begin $display("FAIL priv low-flags: N=%b exp 1 (low flags still write in user)", cc_q[3]); errors=errors+1; end
        nop_ctrl; cc_write_n=oh4(3); z_lo=8'h90; tick;       // OR_MASK tries to set M,I -> held
        if (cc_q[7] !== 1'b0 || cc_q[4] !== 1'b0) begin $display("FAIL priv OR_MASK: user set M/I=%b,%b (must stay 0)", cc_q[7], cc_q[4]); errors=errors+1; end
        nop_ctrl; cc_mi_n=oh4(2); tick;                      // SET_I (SEI) in user -> ignored
        if (cc_q[4] !== 1'b0) begin $display("FAIL priv SET_I: user set I=%b (must stay 0)", cc_q[4]); errors=errors+1; end

        if (errors == 0)
            $display("PASS - cc: reset, FLAG_WE writes, V/C_SRC, Z_ACCUM, 7 conditions, WHOLE_Z/AND/OR, SET_I/CLR_I, M/I privilege");
        else
            $fatal(1, "cc: %0d check(s) FAILED", errors);
        $finish;
    end

    initial begin #200000; $fatal(1, "TIMEOUT - cc bench"); end
endmodule
`default_nettype wire
