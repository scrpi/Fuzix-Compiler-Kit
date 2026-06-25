// cc_conditions — derives the CC microconditions the microsequencer branches on, from the
// live CC register. Structural netlist of real chips (R-SIM-1, R-SIM-5; microcode.md §2).
//
// These are condition cond[6:0] of the sequencer's 16:1 condition mux (cond[7]=TRUE is forced
// inside the sequencer; cond[15:8] are the internal microconditions — IRQ/ULOOP/… — sourced
// elsewhere). UCOND_SEL picks one; UCOND_POL gives both senses (e.g. BEQ vs BNE). The four
// derived conditions are the unsigned/signed compare predicates:
//
//   cond[0] Z            BEQ/BNE
//   cond[1] C            BCS/BCC                      (borrow convention: C=1 => lower)
//   cond[2] N            BMI/BPL
//   cond[3] V            BVS/BVC
//   cond[4] C_OR_Z       BLS/BHI   (unsigned <= )     = C | Z
//   cond[5] N_XOR_V      BLT/BGE   (signed  < )       = N ^ V
//   cond[6] Z_OR_NXORV   BLE/BGT   (signed  <= )      = Z | (N ^ V)
//
// CC bit layout (isa.md §8.4): cc_q[7]=M [5]=H [4]=I [3]=N [2]=Z [1]=V [0]=C.
`timescale 1ns/1ps
`default_nettype none
module cc_conditions (
    input  wire [7:0] cc_q,
    output wire [6:0] cond          // CC-derived microconditions (sequencer cond[6:0])
);
    wire n = cc_q[3], z = cc_q[2], v = cc_q[1], c = cc_q[0];

    wire [3:0] orc;                 // C_OR_Z (and a spare)
    (* purpose = "C_OR_Z" *)
    sn74ahct32 cor (.a({3'b0, c}), .b({3'b0, z}), .y(orc));
    wire [3:0] xnv;                 // N_XOR_V
    (* purpose = "N_XOR_V" *)
    sn74ahct86 cxor (.a({3'b0, n}), .b({3'b0, v}), .y(xnv));
    wire [3:0] orz;                 // Z_OR_NXORV (distinct package from N_XOR_V)
    (* purpose = "Z_OR_NXORV" *)
    sn74ahct32 corz (.a({3'b0, z}), .b({3'b0, xnv[0]}), .y(orz));

    assign cond[0] = z;             // Z
    assign cond[1] = c;             // C
    assign cond[2] = n;             // N
    assign cond[3] = v;             // V
    assign cond[4] = orc[0];        // C_OR_Z
    assign cond[5] = xnv[0];        // N_XOR_V
    assign cond[6] = orz[0];        // Z_OR_NXORV
endmodule
`default_nettype wire
