// cpu — BLIP top-level (SCAFFOLD). Boots its microcode, then runs. Self-contained:
// it instantiates its own boot EEPROM and control store, so the testbench only has to
// supply a clock, a reset, and the checks.
//
// The power-on handoff is driven entirely by uc_loader's `loading` output (the decoder's
// seg-13 line, which the loader's counter latches by halting). `loading` IS the boot/run
// state — there is no separate state machine. It fans out:
//   loading=1 (BOOT): the loader copies the EEPROM into the control store. The address
//     mux selects the loader's counter; control-store /OE is HIGH (SRAMs written, not
//     driving); the isolation buffers drive the SRAM I/O; the micro-PC is held at 0.
//   loading=0 (RUN):  copy done. The mux selects the micro-PC; /OE goes LOW (the SRAMs
//     drive the control word); the buffers tri-state; the micro-PC is released and walks
//     the store. A system reset re-clears the loader's counter -> loading back to 1, so
//     reset re-runs the copy for free.
//
// Structure (all real chips):
//   sst39sf010a     -> the boot EEPROM (pre-burned with the microcode image, param FILE).
//   uc_loader       -> copies EEPROM -> control store at power-on; emits `loading`.
//   sn74ahct04      -> run = ~loading (releases the micro-PC).
//   4x cd74act161   -> the 13-bit micro-PC (CLR# = run; held at 0 in boot, counts in run).
//   4x sn74ahct157  -> the 13-bit control-store address mux (SELECT = loading).
//   4x sn74ahct32   -> the per-chip /WE strobe (cs_sel_n[g] | clk).
//   13x is61c64     -> the control store (11 WCS + 2 opcode-map SRAMs).
//   13x sn74ahct541 -> per-chip boot-write isolation buffers: the EEPROM byte fans out to
//                      all 13 SRAMs during boot (enable = run), tri-stated during run so
//                      each SRAM drives its own control-word byte without contention.
//
// SCAFFOLD: the micro-PC is a linear counter standing in for the real sequencer (no
// dispatch, branch, or opcode-map addressing yet), and `cw` is exposed for observation
// until the datapath that consumes the control word exists.
`timescale 1ns/1ps
`default_nettype none
module cpu #(
    parameter FILE = ""              // the microcode image burned into the EEPROM
) (
    input  wire         clk,
    input  wire         rst_n,       // active-low power-on reset
    // observability (no functional interface yet)
    output wire         loading,     // HIGH while the boot copy runs
    output wire [12:0]  upc,         // the micro-PC once running
    output wire [103:0] cw           // the 13-byte control word read from the store
);
    localparam NSEG  = 13;           // 11 WCS + 2 opcode-map
    localparam DEPTH = 8192;

    wire [16:0]     rom_addr;
    wire [7:0]      rom_data;
    wire [12:0]     loader_addr;     // loader's control-store address during boot
    wire [7:0]      loader_wdata;    // loader's boot write data (= the EEPROM byte)
    wire [NSEG-1:0] cs_sel_n;        // per-chip select (active low) from the loader
    wire            run;             // = ~loading
    wire [12:0]     cs_addr;         // muxed control-store address
    wire [NSEG-1:0] we_n;            // per-chip /WE strobe

    // --- boot EEPROM (pre-burned) -------------------------------------------
    sst39sf010a #(.AW(17), .DW(8), .FILE(FILE), .LOADW(NSEG*DEPTH)) eeprom (
        .a(rom_addr), .dq(rom_data), .ce_n(1'b0), .oe_n(1'b0), .we_n(1'b1)
    );

    // --- boot loader: EEPROM -> control store, emits `loading` --------------
    uc_loader loader (
        .clk(clk), .rst_n(rst_n),
        .rom_addr(rom_addr), .rom_data(rom_data),
        .sram_addr(loader_addr), .sram_wdata(loader_wdata),
        .cs_n(cs_sel_n), .loading(loading)
    );

    // --- run = ~loading (release the micro-PC) ------------------------------
    wire [5:0] inv_y;
    sn74ahct04 inv (.a({5'b0, loading}), .y(inv_y));
    assign run = inv_y[0];

    // --- micro-PC: 4x '161, held at 0 (CLR# = run) during boot --------------
    wire [15:0] upc_q;
    wire [3:0]  upc_rco;
    cd74act161 u0 (.clk(clk), .clr_n(run), .load_n(1'b1), .enp(1'b1), .ent(1'b1),
                   .p(4'b0), .q(upc_q[3:0]),   .rco(upc_rco[0]));
    cd74act161 u1 (.clk(clk), .clr_n(run), .load_n(1'b1), .enp(1'b1), .ent(upc_rco[0]),
                   .p(4'b0), .q(upc_q[7:4]),   .rco(upc_rco[1]));
    cd74act161 u2 (.clk(clk), .clr_n(run), .load_n(1'b1), .enp(1'b1), .ent(upc_rco[1]),
                   .p(4'b0), .q(upc_q[11:8]),  .rco(upc_rco[2]));
    cd74act161 u3 (.clk(clk), .clr_n(run), .load_n(1'b1), .enp(1'b1), .ent(upc_rco[2]),
                   .p(4'b0), .q(upc_q[15:12]), .rco(upc_rco[3]));
    assign upc = upc_q[12:0];

    // --- control-store address mux: SELECT=loading ? loader cnt : micro-PC --
    wire [15:0] mux_a = {3'b000, upc};
    wire [15:0] mux_b = {3'b000, loader_addr};
    wire [15:0] mux_y;
    sn74ahct157 m0 (.a(mux_a[3:0]),   .b(mux_b[3:0]),   .sel(loading), .g_n(1'b0), .y(mux_y[3:0]));
    sn74ahct157 m1 (.a(mux_a[7:4]),   .b(mux_b[7:4]),   .sel(loading), .g_n(1'b0), .y(mux_y[7:4]));
    sn74ahct157 m2 (.a(mux_a[11:8]),  .b(mux_b[11:8]),  .sel(loading), .g_n(1'b0), .y(mux_y[11:8]));
    sn74ahct157 m3 (.a(mux_a[15:12]), .b(mux_b[15:12]), .sel(loading), .g_n(1'b0), .y(mux_y[15:12]));
    assign cs_addr = mux_y[12:0];

    // --- per-chip /WE strobe: cs_sel_n[g] | clk  (4x '32, clk fanned out) ----
    wire [15:0] we_pad;
    sn74ahct32 w0 (.a(cs_sel_n[3:0]),      .b({4{clk}}), .y(we_pad[3:0]));
    sn74ahct32 w1 (.a(cs_sel_n[7:4]),      .b({4{clk}}), .y(we_pad[7:4]));
    sn74ahct32 w2 (.a(cs_sel_n[11:8]),     .b({4{clk}}), .y(we_pad[11:8]));
    sn74ahct32 w3 (.a({3'b000, cs_sel_n[12]}), .b({4{clk}}), .y(we_pad[15:12]));
    assign we_n = we_pad[12:0];

    // --- control store: 13 SRAMs + 13 boot-write isolation buffers ----------
    wire [7:0] io [0:NSEG-1];
    genvar g;
    generate for (g = 0; g < NSEG; g = g + 1) begin : chip
        // boot: drive the EEPROM byte onto this SRAM's I/O (enable = run = ~loading);
        // run: tri-state so the SRAM drives its own control-word byte.
        sn74ahct541 wbuf (.a(loader_wdata), .oe1_n(run), .oe2_n(1'b0), .y(io[g]));
        // /CE tied low; /OE = loading (write in boot, read in run); /WE per-chip strobe.
        is61c64 #(.AW(13), .DW(8)) sram (
            .a(cs_addr), .io(io[g]), .ce_n(1'b0), .oe_n(loading), .we_n(we_n[g])
        );
        assign cw[8*g +: 8] = io[g];
    end endgenerate
endmodule
`default_nettype wire
