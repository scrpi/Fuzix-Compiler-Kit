// alu_logic — the logic section of the ALU: AND / OR / EOR / COM. Structural netlist of real
// chips (R-SIM-1, R-SIM-5; hardware.md §2 "logic-op mux").
//
// Each op's result drives the shared ALU result bus `z` through a tri-state buffer gated by
// that op's decoded strobe (the wired-OR result mux). COM is ~LEFT (LEFT XOR all-ones). The
// N/Z flags come from the result bus at the top; logic ops don't set C/H and force V=0 via
// V_SRC on the CC board, so this block produces no flags.
`timescale 1ns/1ps
`default_nettype none
module alu_logic (
    input  wire [15:0] left,
    input  wire [15:0] right,
    input  wire [3:0]  op_n,        // {COM,EOR,OR,AND} active-low strobes = alu_op_n[9:6]
    output wire [15:0] z            // tri-state: drives the result bus when its op runs
);
    wire [15:0] and_out, or_out, eor_out, com_out;
    (* purpose = "AND [3:0]" *)   sn74ahct08 an0 (.a(left[3:0]),   .b(right[3:0]),   .y(and_out[3:0]));
    (* purpose = "AND [7:4]" *)   sn74ahct08 an1 (.a(left[7:4]),   .b(right[7:4]),   .y(and_out[7:4]));
    (* purpose = "AND [11:8]" *)  sn74ahct08 an2 (.a(left[11:8]),  .b(right[11:8]),  .y(and_out[11:8]));
    (* purpose = "AND [15:12]" *) sn74ahct08 an3 (.a(left[15:12]), .b(right[15:12]), .y(and_out[15:12]));
    (* purpose = "OR [3:0]" *)    sn74ahct32 o0 (.a(left[3:0]),   .b(right[3:0]),   .y(or_out[3:0]));
    (* purpose = "OR [7:4]" *)    sn74ahct32 o1 (.a(left[7:4]),   .b(right[7:4]),   .y(or_out[7:4]));
    (* purpose = "OR [11:8]" *)   sn74ahct32 o2 (.a(left[11:8]),  .b(right[11:8]),  .y(or_out[11:8]));
    (* purpose = "OR [15:12]" *)  sn74ahct32 o3 (.a(left[15:12]), .b(right[15:12]), .y(or_out[15:12]));
    (* purpose = "EOR [3:0]" *)   sn74ahct86 e0 (.a(left[3:0]),   .b(right[3:0]),   .y(eor_out[3:0]));
    (* purpose = "EOR [7:4]" *)   sn74ahct86 e1 (.a(left[7:4]),   .b(right[7:4]),   .y(eor_out[7:4]));
    (* purpose = "EOR [11:8]" *)  sn74ahct86 e2 (.a(left[11:8]),  .b(right[11:8]),  .y(eor_out[11:8]));
    (* purpose = "EOR [15:12]" *) sn74ahct86 e3 (.a(left[15:12]), .b(right[15:12]), .y(eor_out[15:12]));
    (* purpose = "COM [3:0]" *)   sn74ahct86 c0 (.a(left[3:0]),   .b(4'hF), .y(com_out[3:0]));
    (* purpose = "COM [7:4]" *)   sn74ahct86 c1 (.a(left[7:4]),   .b(4'hF), .y(com_out[7:4]));
    (* purpose = "COM [11:8]" *)  sn74ahct86 c2 (.a(left[11:8]),  .b(4'hF), .y(com_out[11:8]));
    (* purpose = "COM [15:12]" *) sn74ahct86 c3 (.a(left[15:12]), .b(4'hF), .y(com_out[15:12]));

    // result mux: each logic op tri-states its result onto z (op_n one-hot, active LOW).
    (* purpose = "Z<-AND [7:0]" *)  sn74ahct541 ra0 (.a(and_out[7:0]),  .oe1_n(op_n[0]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-AND [15:8]" *) sn74ahct541 ra1 (.a(and_out[15:8]), .oe1_n(op_n[0]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-OR [7:0]" *)   sn74ahct541 ro0 (.a(or_out[7:0]),   .oe1_n(op_n[1]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-OR [15:8]" *)  sn74ahct541 ro1 (.a(or_out[15:8]),  .oe1_n(op_n[1]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-EOR [7:0]" *)  sn74ahct541 re0 (.a(eor_out[7:0]),  .oe1_n(op_n[2]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-EOR [15:8]" *) sn74ahct541 re1 (.a(eor_out[15:8]), .oe1_n(op_n[2]), .oe2_n(1'b0), .y(z[15:8]));
    (* purpose = "Z<-COM [7:0]" *)  sn74ahct541 rc0 (.a(com_out[7:0]),  .oe1_n(op_n[3]), .oe2_n(1'b0), .y(z[7:0]));
    (* purpose = "Z<-COM [15:8]" *) sn74ahct541 rc1 (.a(com_out[15:8]), .oe1_n(op_n[3]), .oe2_n(1'b0), .y(z[15:8]));
endmodule
`default_nettype wire
