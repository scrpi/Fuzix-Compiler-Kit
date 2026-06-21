// cpu — BLIP top-level (SCAFFOLD). Boots its microcode, then runs.
//
// The power-on handoff is driven entirely by uc_loader's `loading` output (the
// decoder's seg-13 line, which the loader's counter latches by halting). `loading`
// IS the boot/run state — there is no separate state machine. It fans out to three
// places on the control store:
//
//   loading=1 (BOOT): the loader copies the EEPROM into the control store. The
//     address mux selects the loader's counter; the control-store /OE is HIGH (the
//     SRAMs are being written, not driving); the micro-PC is held at 0.
//   loading=0 (RUN):  the copy is done. The address mux selects the micro-PC; /OE
//     goes LOW (the SRAMs drive the control word); the micro-PC is released and
//     walks the control store. A system reset re-clears the loader's counter, which
//     forces loading back to 1 — so reset re-runs the copy for free.
//
// Structure (all real chips):
//   uc_loader      -> copies EEPROM -> control store at power-on; emits `loading`.
//   sn74ahct04     -> run = ~loading (the inverter that releases the micro-PC).
//   4x cd74act161  -> the 13-bit micro-PC: CLR# = run holds it at 0 during boot,
//                     then it counts every cycle during run (ripple-carry cascade).
//   4x sn74ahct157 -> the 13-bit control-store address mux (SELECT = loading).
//
// SCAFFOLD boundary: the EEPROM and the 13 control-store SRAMs are board-attached in
// the testbench (the boot-write data topology — per-chip isolation buffers — is a
// separate, unsettled design), so this module exposes the control-store interface as
// ports. The micro-PC is a linear counter standing in for the real sequencer: no
// dispatch, no branch, no opcode-map addressing yet.
`timescale 1ns/1ps
`default_nettype none
module cpu (
    input  wire        clk,
    input  wire        rst_n,       // active-low power-on reset
    // microcode boot EEPROM (board-attached source)
    output wire [16:0] rom_addr,
    input  wire [7:0]  rom_data,
    // control-store (WCS + opcode-map) SRAM interface (board-attached memory)
    output wire [12:0] cs_addr,      // muxed address: loader cnt (boot) / micro-PC (run)
    output wire [12:0] cs_sel_n,     // per-chip select (active low), for the boot write strobe
    output wire        cs_oe_n,      // control-store /OE (= loading: off in boot, on in run)
    output wire [7:0]  cs_wdata,     // boot write data (= the EEPROM byte)
    // observability
    output wire        loading,      // HIGH while the boot copy runs
    output wire [12:0] upc           // the micro-PC once running
);
    wire [12:0] loader_addr;         // loader's control-store address during boot
    wire        run;                 // = ~loading

    // --- boot loader: EEPROM -> control store, emits `loading` ---------------
    uc_loader loader (
        .clk(clk), .rst_n(rst_n),
        .rom_addr(rom_addr), .rom_data(rom_data),
        .sram_addr(loader_addr), .sram_wdata(cs_wdata),
        .cs_n(cs_sel_n), .loading(loading)
    );

    // --- run = ~loading (release the micro-PC when the copy ends) -----------
    wire [5:0] inv_y;
    sn74ahct04 inv (.a({5'b0, loading}), .y(inv_y));
    assign run = inv_y[0];

    // --- micro-PC: 4x '161, held at 0 (CLR# = run) during boot, counts in run -
    wire [15:0] upc_q;               // 16 bits exist; [12:0] used
    wire [3:0]  upc_rco;             // ripple carry between stages (upc_rco[3] unused)
    cd74act161 u0 (.clk(clk), .clr_n(run), .load_n(1'b1), .enp(1'b1), .ent(1'b1),
                   .p(4'b0), .q(upc_q[3:0]),   .rco(upc_rco[0]));
    cd74act161 u1 (.clk(clk), .clr_n(run), .load_n(1'b1), .enp(1'b1), .ent(upc_rco[0]),
                   .p(4'b0), .q(upc_q[7:4]),   .rco(upc_rco[1]));
    cd74act161 u2 (.clk(clk), .clr_n(run), .load_n(1'b1), .enp(1'b1), .ent(upc_rco[1]),
                   .p(4'b0), .q(upc_q[11:8]),  .rco(upc_rco[2]));
    cd74act161 u3 (.clk(clk), .clr_n(run), .load_n(1'b1), .enp(1'b1), .ent(upc_rco[2]),
                   .p(4'b0), .q(upc_q[15:12]), .rco(upc_rco[3]));
    assign upc = upc_q[12:0];

    // --- control-store address mux: SELECT=loading ? loader cnt : micro-PC ---
    // '157: SELECT=0 -> A (micro-PC), SELECT=1 -> B (loader cnt); /G tied low.
    wire [15:0] mux_a = {3'b000, upc};
    wire [15:0] mux_b = {3'b000, loader_addr};
    wire [15:0] mux_y;
    sn74ahct157 m0 (.a(mux_a[3:0]),   .b(mux_b[3:0]),   .sel(loading), .g_n(1'b0), .y(mux_y[3:0]));
    sn74ahct157 m1 (.a(mux_a[7:4]),   .b(mux_b[7:4]),   .sel(loading), .g_n(1'b0), .y(mux_y[7:4]));
    sn74ahct157 m2 (.a(mux_a[11:8]),  .b(mux_b[11:8]),  .sel(loading), .g_n(1'b0), .y(mux_y[11:8]));
    sn74ahct157 m3 (.a(mux_a[15:12]), .b(mux_b[15:12]), .sel(loading), .g_n(1'b0), .y(mux_y[15:12]));
    assign cs_addr = mux_y[12:0];

    // --- control-store /OE: write during boot (high), read during run (low) --
    assign cs_oe_n = loading;
endmodule
`default_nettype wire
