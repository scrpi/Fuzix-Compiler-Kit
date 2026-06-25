// z_lane — the Z-bus byte-lane steer for a register destination. Structural netlist of real
// chips (R-SIM-1, R-SIM-5; microcode.md §3.2 Z_LANE; cpu-physical-construction.md §6.2).
//
// Z_LANE selects WHICH byte lane a Z-destination register latches when a value is posted on Z:
//   FULL16   load both bytes from Z[15:0]              (a real 16-bit result)
//   LOW (B)  load the low byte only, from Z[7:0]       (high byte held)
//   HIGH (A) load the high byte only, from Z[7:0]      (low byte held)
// A single byte that was computed or read always appears on Z[7:0] (MDR posts a read byte on the
// Z low lane), so promoting it into a register's HIGH lane routes Z[7:0] -> the high byte's load
// inputs. This is what lets a 16-bit value land in a register as two byte cycles (Z_LANE low then
// high) — the byte-cycle memory path of the spec.
//
// The block produces:
//   (a) z_load — the steered load bus a Z-dest register's z_in takes. The low byte is always
//       Z[7:0]; the high byte is Z[7:0] on HIGH (the byte-promote) and Z[15:8] otherwise.
//   (b) block_lo / block_hi — two active-HIGH lane blockers the motherboard ORs into each
//       Z-dest's /load-low and /load-high strobes to suppress the lane that must not load:
//          block_lo = (Z_LANE==HIGH)   -> suppress the low-byte load
//          block_hi = (Z_LANE==LOW)    -> suppress the high-byte load
//       FULL16 asserts neither, so both bytes load — the all-zero default is a full-16 load.
//
// Structure (the BOM): 2x sn74ahct157 (the high-byte source mux), 1x sn74ahct04 (the two blocker
// inversions). The low byte z_load[7:0] = Z[7:0] is pure wiring.
`timescale 1ns/1ps
`default_nettype none
module z_lane (
    input  wire [15:0] z,            // the Z bus (ALU result / posted value)
    input  wire [3:0]  z_lane_n,     // decoded Z_LANE one-hot, active LOW:
                                     //   [0]=FULL16 [1]=LOW [2]=HIGH
    output wire [15:0] z_load,       // steered load bus -> a Z-dest register's z_in
    output wire        block_lo,     // 1 = suppress the low-byte load  (Z_LANE==HIGH)
    output wire        block_hi      // 1 = suppress the high-byte load (Z_LANE==LOW)
);
    // ---- low lane: always Z[7:0] (pure wiring) ----------------------------------
    assign z_load[7:0] = z[7:0];

    // ---- high-byte source: HIGH (SEL=0) -> Z[7:0] (byte-promote); else -> Z[15:8]
    (* purpose = "Z high src: byte-promote? [3:0]" *)
    sn74ahct157 zh0 (.a(z[3:0]), .b(z[11:8]),  .sel(z_lane_n[2]), .g_n(1'b0), .y(z_load[11:8]));
    (* purpose = "Z high src: byte-promote? [7:4]" *)
    sn74ahct157 zh1 (.a(z[7:4]), .b(z[15:12]), .sel(z_lane_n[2]), .g_n(1'b0), .y(z_load[15:12]));

    // ---- lane blockers: active-HIGH "suppress this byte's load" ------------------
    // block_lo = ~z_lane_n[2] (Z_LANE==HIGH);  block_hi = ~z_lane_n[1] (Z_LANE==LOW).
    wire [5:0] nb;
    (* purpose = "Z_LANE blockers (invert)" *)
    sn74ahct04 blk (.a({4'b0000, z_lane_n[1], z_lane_n[2]}), .y(nb));
    assign block_lo = nb[0];
    assign block_hi = nb[1];
endmodule
`default_nettype wire
