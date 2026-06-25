// right_bus — the ALU's RIGHT source bus: the two scratch registers SCR1/SCR2 plus the
// constant generator {-2,-1,0,+1,+2}, selected by RIGHT_SRC. Structural netlist of real chips
// (R-SIM-1, R-SIM-5; hardware.md §2 "asymmetric source buses" + "constant generator"; D-36).
//
// RIGHT is the cheap, sparsely-driven ALU input: only the scratch registers and the constant
// generator drive it (hardware.md §2), so reg±1/±2 and reg+0 (= move) are single ALU ops on
// ANY register with no register tied up holding a small constant; the ±2 cases cover 16-bit
// SP steps and word-pointer ++/-- (D-36). Each source tri-states onto the bus through a buffer
// gated by its decoded RIGHT_SRC strobe (the wired-OR mux, same pattern as the ALU result bus).
// The constants are hardwired patterns driven through their buffers — that IS the const-gen.
//
// SCR1/SCR2 are the universal '163 register board (register16), instantiated on the ALU board;
// this module takes their values and forms the RIGHT bus. RIGHT stays local to the ALU board
// (cpu-physical-construction.md §3.2), so it is not a motherboard bus.
//
// RIGHT_SRC one-hot (active LOW): [0]=SCR1 [1]=SCR2 [2]=-2 [3]=-1 [4]=0 [5]=+1 [6]=+2.
`timescale 1ns/1ps
`default_nettype none
module right_bus (
    input  wire [15:0] scr1,            // scratch register 1 value
    input  wire [15:0] scr2,            // scratch register 2 value
    input  wire [7:0]  right_src_n,     // decoded RIGHT_SRC one-hot, active LOW
    output wire [15:0] right            // the RIGHT bus
);
    (* purpose = "RIGHT<-SCR1 [7:0]" *)  sn74ahct541 s1lo (.a(scr1[7:0]),  .oe1_n(right_src_n[0]), .oe2_n(1'b0), .y(right[7:0]));
    (* purpose = "RIGHT<-SCR1 [15:8]" *) sn74ahct541 s1hi (.a(scr1[15:8]), .oe1_n(right_src_n[0]), .oe2_n(1'b0), .y(right[15:8]));
    (* purpose = "RIGHT<-SCR2 [7:0]" *)  sn74ahct541 s2lo (.a(scr2[7:0]),  .oe1_n(right_src_n[1]), .oe2_n(1'b0), .y(right[7:0]));
    (* purpose = "RIGHT<-SCR2 [15:8]" *) sn74ahct541 s2hi (.a(scr2[15:8]), .oe1_n(right_src_n[1]), .oe2_n(1'b0), .y(right[15:8]));
    // const-gen: hardwired patterns driven onto RIGHT through their buffers.
    (* purpose = "RIGHT<- -2 [7:0]" *)   sn74ahct541 m2lo (.a(8'hFE), .oe1_n(right_src_n[2]), .oe2_n(1'b0), .y(right[7:0]));
    (* purpose = "RIGHT<- -2 [15:8]" *)  sn74ahct541 m2hi (.a(8'hFF), .oe1_n(right_src_n[2]), .oe2_n(1'b0), .y(right[15:8]));
    (* purpose = "RIGHT<- -1 [7:0]" *)   sn74ahct541 m1lo (.a(8'hFF), .oe1_n(right_src_n[3]), .oe2_n(1'b0), .y(right[7:0]));
    (* purpose = "RIGHT<- -1 [15:8]" *)  sn74ahct541 m1hi (.a(8'hFF), .oe1_n(right_src_n[3]), .oe2_n(1'b0), .y(right[15:8]));
    (* purpose = "RIGHT<- 0 [7:0]" *)    sn74ahct541 z0lo (.a(8'h00), .oe1_n(right_src_n[4]), .oe2_n(1'b0), .y(right[7:0]));
    (* purpose = "RIGHT<- 0 [15:8]" *)   sn74ahct541 z0hi (.a(8'h00), .oe1_n(right_src_n[4]), .oe2_n(1'b0), .y(right[15:8]));
    (* purpose = "RIGHT<- +1 [7:0]" *)   sn74ahct541 p1lo (.a(8'h01), .oe1_n(right_src_n[5]), .oe2_n(1'b0), .y(right[7:0]));
    (* purpose = "RIGHT<- +1 [15:8]" *)  sn74ahct541 p1hi (.a(8'h00), .oe1_n(right_src_n[5]), .oe2_n(1'b0), .y(right[15:8]));
    (* purpose = "RIGHT<- +2 [7:0]" *)   sn74ahct541 p2lo (.a(8'h02), .oe1_n(right_src_n[6]), .oe2_n(1'b0), .y(right[7:0]));
    (* purpose = "RIGHT<- +2 [15:8]" *)  sn74ahct541 p2hi (.a(8'h00), .oe1_n(right_src_n[6]), .oe2_n(1'b0), .y(right[15:8]));
endmodule
`default_nettype wire
