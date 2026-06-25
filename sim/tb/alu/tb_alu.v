// alu testbench (Icarus -gspecify, TIMED; D-47) — the 16-bit compute core.
//
// Combinational DUT: drive LEFT/RIGHT/op/width/cin, settle, check Z and the N/Z/V/C/H flags
// against a behavioural reference computed the same way the hardware forms them (two's-
// complement add with conditional B-invert, borrow-convention carry, V from the sign bits).
// Covers ADD/ADC/SUB/SBC/NEG (W8 + W16, carry/borrow/overflow/half-carry), AND/OR/EOR/COM,
// and the PASS_L/PASS_R moves.
`timescale 1ns/1ps
`default_nettype none
module tb_alu;
    // op encodings (ALU_OP); the DUT takes the one-hot, active-low form ~(1<<op).
    localparam ADD=2, ADC=3, SUB=4, SBC=5, AND_=6, OR_=7, EOR=8, COM=9, NEG=10, PASSL=0, PASSR=1;

    reg  [15:0] left, right;
    reg  [15:0] op_n;
    reg         cinf, width, ccc;
    wire [15:0] z;
    wire        fn, fz, fv, fc, fh;

    alu dut (
        .left(left), .right(right), .alu_op_n(op_n), .alu_cin(cinf), .alu_width(width), .cc_c(ccc),
        .z(z), .flag_n(fn), .flag_z(fz), .flag_v(fv), .flag_c(fc), .flag_h(fh)
    );

    integer errors = 0;
    // reference state
    reg [16:0] full; reg [15:0] aa, bb, ez; reg ebinv, ec16, ec8, ec4, en, ezf, ev, efc, efh;

    task drive(input [3:0] op, input [15:0] L, input [15:0] R, input ci, input w, input c);
        begin left=L; right=R; cinf=ci; width=w; ccc=c; op_n = ~(16'd1 << op); #300; end  // settle adder ripple + flag-reduction tree
    endtask

    // arithmetic check: build the same A/B/cin the hardware does, then compare flags.
    task chk_arith(input [3:0] op, input [15:0] L, input [15:0] R, input ci, input w, input c);
        reg cval; reg [3:0] al, bl;
        begin
            drive(op, L, R, ci, w, c);
            // operand conditioning
            aa = (op==NEG) ? 16'h0000 : L;
            bb = ((op==SUB)||(op==SBC)) ? ~R : ((op==NEG) ? ~L : R);
            ebinv = (op==SUB)||(op==SBC)||(op==NEG);
            cval = (op==ADD) ? (ci ? c : 1'b0)
                 : (op==ADC) ? c
                 : (op==SUB) ? 1'b1
                 : (op==SBC) ? c
                 : /*NEG*/      1'b1;
            full = aa + bb + cval;
            ez  = full[15:0];
            ec16 = full[16];
            ec8  = ((aa[7:0]  + bb[7:0]  + cval) >> 8) & 1;
            ec4  = ((aa[3:0]  + bb[3:0]  + cval) >> 4) & 1;
            efh  = ec4;
            // width-selected flags
            en   = w ? ez[15] : ez[7];
            ezf  = w ? (ez==16'h0) : (ez[7:0]==8'h0);
            ev   = w ? (aa[15]^bb[15]^ez[15]^ec16) : (aa[7]^bb[7]^ez[7]^ec8);
            efc  = (w ? ec16 : ec8) ^ ebinv;
            if (z !== ez)  begin $display("FAIL op%0d %04x,%04x w%0d: Z=%04x exp %04x", op,L,R,w,z,ez); errors=errors+1; end
            if (fn !== en) begin $display("FAIL op%0d %04x,%04x w%0d: N=%b exp %b", op,L,R,w,fn,en); errors=errors+1; end
            if (fz !== ezf)begin $display("FAIL op%0d %04x,%04x w%0d: Z flag=%b exp %b", op,L,R,w,fz,ezf); errors=errors+1; end
            if (fv !== ev) begin $display("FAIL op%0d %04x,%04x w%0d: V=%b exp %b", op,L,R,w,fv,ev); errors=errors+1; end
            if (fc !== efc)begin $display("FAIL op%0d %04x,%04x w%0d: C=%b exp %b", op,L,R,w,fc,efc); errors=errors+1; end
            if (w==1'b0 && fh !== efh) begin $display("FAIL op%0d %04x,%04x: H=%b exp %b", op,L,R,fh,efh); errors=errors+1; end
        end
    endtask

    // logic/move check: only Z and the N/Z flags are the ALU's responsibility here.
    task chk_log(input [3:0] op, input [15:0] L, input [15:0] R, input w, input [15:0] expz);
        begin
            drive(op, L, R, 1'b0, w, 1'b0);
            if (z !== expz) begin $display("FAIL op%0d %04x,%04x: Z=%04x exp %04x", op,L,R,z,expz); errors=errors+1; end
            if (fn !== (w?expz[15]:expz[7])) begin $display("FAIL op%0d: N wrong", op); errors=errors+1; end
            if (fz !== (w?(expz==0):(expz[7:0]==0))) begin $display("FAIL op%0d: Z flag wrong", op); errors=errors+1; end
        end
    endtask

    initial begin
        // ---- ADD ----
        chk_arith(ADD, 16'h1234, 16'h1111, 0, 1, 0);   // plain
        chk_arith(ADD, 16'hFFFF, 16'h0001, 0, 1, 0);   // carry out + zero
        chk_arith(ADD, 16'h7FFF, 16'h0001, 0, 1, 0);   // signed overflow -> 0x8000
        chk_arith(ADD, 16'h00FF, 16'h0001, 0, 0, 0);   // W8: carry, half-carry, zero low byte
        chk_arith(ADD, 16'h1234, 16'h1111, 1, 1, 1);   // ALU_CIN=CC_C, C=1 -> +1
        // ---- ADC ----
        chk_arith(ADC, 16'h1234, 16'h1111, 0, 1, 1);   // +C
        chk_arith(ADC, 16'h1234, 16'h1111, 0, 1, 0);   // +0
        // ---- SUB ----
        chk_arith(SUB, 16'h5000, 16'h1000, 0, 1, 0);   // no borrow
        chk_arith(SUB, 16'h1000, 16'h5000, 0, 1, 0);   // borrow
        chk_arith(SUB, 16'h1234, 16'h1234, 0, 1, 0);   // equal -> zero, no borrow
        chk_arith(SUB, 16'h0010, 16'h0001, 0, 0, 0);   // W8
        // ---- SBC ----
        chk_arith(SBC, 16'h5000, 16'h1000, 0, 1, 1);   // C=1 -> like SUB
        chk_arith(SBC, 16'h5000, 16'h1000, 0, 1, 0);   // C=0 -> one less
        // ---- NEG ----
        chk_arith(NEG, 16'h0001, 16'h0000, 0, 1, 0);   // -1 -> 0xFFFF, borrow
        chk_arith(NEG, 16'h0000, 16'h0000, 0, 1, 0);   // -0 -> 0, no borrow
        chk_arith(NEG, 16'h0080, 16'h0000, 0, 0, 0);   // W8 neg
        // ---- logic + moves ----
        chk_log(AND_, 16'hFF0F, 16'h0FF0, 1, 16'h0F00);
        chk_log(OR_,  16'hFF00, 16'h00FF, 1, 16'hFFFF);
        chk_log(EOR,  16'hFFFF, 16'h0F0F, 1, 16'hF0F0);
        chk_log(COM,  16'h1234, 16'h0000, 1, 16'hEDCB);
        chk_log(PASSL,16'hCAFE, 16'h0000, 1, 16'hCAFE);
        chk_log(PASSR,16'h0000, 16'hBEEF, 1, 16'hBEEF);

        if (errors == 0)
            $display("PASS - alu: ADD/ADC/SUB/SBC/NEG (W8+W16, C/borrow/V/H) + AND/OR/EOR/COM + PASS");
        else
            $fatal(1, "alu: %0d check(s) FAILED", errors);
        $finish;
    end

    initial begin #2000000; $fatal(1, "TIMEOUT - alu bench"); end
endmodule
`default_nettype wire
