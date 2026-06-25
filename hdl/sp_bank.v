// sp_bank — the active-stack-pointer bank resolver (hardware.md §2; cpu-physical-construction.md
// §6.4(b)). Structural netlist of real chips (R-SIM-1, R-SIM-5; R-CPU-4/-6).
//
// The active SP is whichever of USP/SSP the privilege mode picks; ACTIVE_SP (LEFT_SRC=14 /
// Z_DEST=4) names it without the microcode knowing the bank. The bank choice resolves OFF the
// register boards (they are identical) — this block does it, handing each SP board a single
// already-bank-resolved enable, exactly as the spec requires "no bank logic on the board".
//
//   use_ssp = CC.M | SP_BANK    (supervisor, or SP_BANK=FORCE_SSP -> the supervisor stack)
// An ACTIVE_SP reference then routes to SSP when use_ssp, else to USP. Each board's final enable
// is its EXPLICIT strobe (LEFT_SRC/Z_DEST = USP/SSP) OR'd with the routed ACTIVE_SP strobe — and
// because the strobes are active LOW, "OR" is a single AND gate (output low if either is low).
//
// Structure (the BOM): 1x '32 (use_ssp), 1x '04 (use_usp), 1x '32 (the four ACTIVE_SP routes),
// 1x '08 (the four explicit|routed merges).
`timescale 1ns/1ps
`default_nettype none
module sp_bank (
    input  wire cc_m,              // CC.M (1 = supervisor)
    input  wire sp_bank,           // SP_BANK (1 = FORCE_SSP)
    // explicit per-board strobes (active LOW, decoded LEFT_SRC / Z_DEST)
    input  wire left_active_sp_n,  // LEFT_SRC == ACTIVE_SP
    input  wire left_usp_n,        // LEFT_SRC == USP
    input  wire left_ssp_n,        // LEFT_SRC == SSP
    input  wire z_active_sp_n,     // Z_DEST  == ACTIVE_SP
    input  wire z_usp_n,           // Z_DEST  == USP
    input  wire z_ssp_n,           // Z_DEST  == SSP
    // bank-resolved board enables (active LOW)
    output wire usp_drive_n, ssp_drive_n,   // LEFT drive
    output wire usp_load_n,  ssp_load_n     // Z load (full16)
);
    // use_ssp = CC.M | SP_BANK ; use_usp = ~use_ssp
    wire [3:0] uss;
    (* purpose = "use_ssp = M | SP_BANK" *)
    sn74ahct32 us (.a({3'b0, cc_m}), .b({3'b0, sp_bank}), .y(uss));
    wire use_ssp = uss[0];
    wire [5:0] iv;
    (* purpose = "use_usp = ~use_ssp" *)
    sn74ahct04 ui (.a({5'b0, use_ssp}), .y(iv));
    wire use_usp = iv[0];

    // ACTIVE_SP routes (active LOW): asserted when ACTIVE_SP selected AND this bank is active.
    //   route_ssp_n = active_sp_n | use_usp   (LOW only when active_sp_n=0 AND use_ssp=1)
    //   route_usp_n = active_sp_n | use_ssp   (LOW only when active_sp_n=0 AND use_usp=1)
    wire [3:0] rt;
    (* purpose = "ACTIVE_SP -> USP/SSP routes (LEFT,Z)" *)
    sn74ahct32 rte (.a({z_active_sp_n,  z_active_sp_n,  left_active_sp_n, left_active_sp_n}),
                    .b({use_usp,        use_ssp,        use_usp,          use_ssp}),
                    .y(rt));
    wire as_l_usp_n = rt[0], as_l_ssp_n = rt[1], as_z_usp_n = rt[2], as_z_ssp_n = rt[3];

    // final enable = explicit strobe AND routed ACTIVE_SP strobe (active-low OR).
    wire [3:0] en;
    (* purpose = "explicit | ACTIVE_SP per board" *)
    sn74ahct08 ena (.a({z_ssp_n,    z_usp_n,    left_ssp_n,  left_usp_n}),
                    .b({as_z_ssp_n, as_z_usp_n, as_l_ssp_n,  as_l_usp_n}),
                    .y(en));
    assign usp_drive_n = en[0];
    assign ssp_drive_n = en[1];
    assign usp_load_n  = en[2];
    assign ssp_load_n  = en[3];
endmodule
`default_nettype wire
