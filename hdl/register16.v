// register16 — the universal 16-bit register board (cpu-physical-construction.md §6): one
// form factor that serves every architectural register. Structural netlist of real chips
// (R-SIM-1, R-SIM-5; R-HW-4 — individually-observable discrete register; D-36).
//
// Built around the off-bus +1 counter as a SUPERSET storage element (§6.1): a counter does
// load / count / hold, a plain latch does only load / hold, so one counter board covers both
// the registers that need off-bus +1 (X, Y, and PC/MAR which assert count) and those that do
// not (D, USP, SSP — they simply never assert count). Uniformity for a few unused gates.
//
// Independent per-byte load (§6.2/§6.3): the low and high '163 pairs take SEPARATE load
// enables (/PE split), so a microword can load the low byte, the high byte, or both — the
// byte-cycle memory path and the A:B accumulator both rely on it. A FULL16 load asserts both.
//
// Structure (the BOM, §6.2):
//   4x cd74act163  -> 16-bit storage; cascaded ENP/ENT ripple-carry for a synchronous +1;
//                     SYNCHRONOUS clear on /RESET for the deterministic power-on state (R-CPU-7).
//   2x sn74ahct244  -> the LEFT driver (§6.2): gate the 16-bit value onto LEFT, both 4-bit
//                     group enables tied to the single decoded drive-LEFT strobe.
//
// The '163 Q outputs are permanent, so `q` feeds the panel LEDs / shadow and any second
// output port (the PC/MAR variant taps `q` for the MMU, §6.6) directly, in parallel with
// the tri-state LEFT driver.
//
// Enables arrive ALREADY DECODED from the motherboard (§3.3/§6.3), at the '163 pin polarity:
// load_lo_n/load_hi_n and drive_left_n active LOW (straight to /PE and the '541 /OE),
// count_en active HIGH (to ENP). The field->enable decode and any polarity glue live on the
// motherboard (cpu.v), keeping this board a pure register.
`timescale 1ns/1ps
`default_nettype none
module register16 (
    input  wire        clk,
    input  wire        reset_n,        // SYNCHRONOUS clear (active LOW) -> Q = 0 on the clk edge
    input  wire [15:0] z_in,           // load source (the Z bus)
    input  wire        load_lo_n,      // load low byte from Z   (active LOW)
    input  wire        load_hi_n,      // load high byte from Z  (active LOW)
    input  wire        count_en,       // count +1               (active HIGH)
    input  wire        drive_left_n,   // gate Q onto LEFT       (active LOW)
    output wire [15:0] q,              // the register value (permanent — LEDs / 2nd port)
    output wire [15:0] left_out        // Q onto LEFT (3-state; driven when drive_left_n LOW)
);
    // ---- 16-bit storage: four '163s, ripple-carry cascade, split /PE per byte ----
    // ENP = count_en on every stage; ENT chains through RCO so the carry is synchronous.
    // Low pair (q[7:0]) loads on load_lo_n; high pair (q[15:8]) on load_hi_n.
    wire [2:0] rco;                    // stage carries (top stage's RCO unused)
    (* purpose = "reg bits [3:0]" *)
    cd74act163 r0 (.clk(clk), .clr_n(reset_n), .load_n(load_lo_n), .enp(count_en), .ent(count_en),
                   .p(z_in[3:0]),   .q(q[3:0]),   .rco(rco[0]));
    (* purpose = "reg bits [7:4]" *)
    cd74act163 r1 (.clk(clk), .clr_n(reset_n), .load_n(load_lo_n), .enp(count_en), .ent(rco[0]),
                   .p(z_in[7:4]),   .q(q[7:4]),   .rco(rco[1]));
    (* purpose = "reg bits [11:8]" *)
    cd74act163 r2 (.clk(clk), .clr_n(reset_n), .load_n(load_hi_n), .enp(count_en), .ent(rco[1]),
                   .p(z_in[11:8]),  .q(q[11:8]),  .rco(rco[2]));
    (* purpose = "reg bits [15:12]" *)
    cd74act163 r3 (.clk(clk), .clr_n(reset_n), .load_n(load_hi_n), .enp(count_en), .ent(rco[2]),
                   .p(z_in[15:12]), .q(q[15:12]), .rco(/*unused*/));

    // ---- LEFT driver: gate the 16-bit value onto LEFT (one decoded enable) --------
    // Each '244 group enable (1OE#/2OE#) ties to the same drive_left_n strobe.
    (* purpose = "LEFT driver [7:0]" *)
    sn74ahct244 lo (.a(q[7:0]),  .oe1_n(drive_left_n), .oe2_n(drive_left_n), .y(left_out[7:0]));
    (* purpose = "LEFT driver [15:8]" *)
    sn74ahct244 hi (.a(q[15:8]), .oe1_n(drive_left_n), .oe2_n(drive_left_n), .y(left_out[15:8]));
endmodule
`default_nettype wire
