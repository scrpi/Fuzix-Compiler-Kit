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
// Structure (the integrator wires real chips + the factored blocks):
//   sst39sf010a     -> the boot EEPROM (pre-burned with the microcode image, param FILE).
//   uc_loader       -> copies EEPROM -> control store at power-on; emits `loading`.
//   sn74ahct04      -> run = ~loading (releases the micro-PC).
//   microsequencer  -> the real 12-bit micro-PC: INC/JUMP/BRANCH/WAIT/DISPATCH_IR (it reads
//                      the control word's sequencer section + the conditions + the LUT).
//   sn74ahct574     -> the 8-bit opcode register IR (drives the opcode-LUT dispatch index).
//   3x sn74ahct157  -> the 12-bit WCS address mux (SELECT = loading ? loader : micro-PC).
//   4x sn74ahct32   -> the per-chip /WE strobe (cs_sel_n[g] | clk).
//   microcode_store -> the 11 WCS SRAMs + boot-write buffers: the 88-bit control word.
//   opcode_lut      -> the 2 opcode->start-address LUT SRAMs (run-addressed by {PAGE, IR}).
//   control_word_decoder -> the datapath section's one-hot strobes (observation only).
//
// SCAFFOLD: the datapath that would drive IR (from a memory fetch) and the condition lines
// (from CC/flags) does not exist yet (hardware.md §2), so the bench injects them via the
// `ir_drive` / `cond_drive` debug taps. CALL/RETURN, the ULOOP loop counter, the trap-vector
// encoder, and the registered (pipelined) control word are deferred (microsequencer.v).
`timescale 1ns/1ps
`default_nettype none
module cpu #(
    parameter FILE = ""              // the microcode image burned into the EEPROM
) (
    input  wire         clk,
    input  wire         rst_n,       // active-low power-on reset
    // privileged debug interface (R-DBG-5) — the datapath that would drive these does not
    // exist yet, so the bench injects the opcode (IR) and the condition lines here.
    input  wire [7:0]   ir_drive,    // opcode into IR (until the fetch datapath loads it)
    input  wire [15:0]  cond_drive,  // CC/microcondition lines (index 7 = TRUE is internal)
    // observability — privileged debug taps (R-DBG-5)
    output wire         loading,     // HIGH while the boot copy runs
    output wire [11:0]  upc,         // the micro-PC once running
    output wire [87:0]  cw,          // the 88-bit control word read from the WCS
    output wire [11:0]  lut_out      // opcode-LUT dispatch target {lut_hi[3:0], lut_lo}
);
    localparam NSEG  = 13;           // 11 WCS + 2 opcode-LUT
    localparam DEPTH = 4096;

    wire [15:0]     rom_addr;
    wire [7:0]      rom_data;
    wire [11:0]     loader_addr;     // loader's control-store address during boot
    wire [7:0]      loader_wdata;    // loader's boot write data (= the EEPROM byte)
    wire [NSEG-1:0] cs_sel_n;        // per-chip select (active low) from the loader
    wire            run;             // = ~loading
    wire [11:0]     cs_addr;         // muxed control-store address
    wire [NSEG-1:0] we_n;            // per-chip /WE strobe

    // --- boot EEPROM (pre-burned) -------------------------------------------
    (* purpose = "boot EEPROM" *)
    sst39sf010a #(.AW(17), .DW(8), .FILE(FILE), .LOADW(NSEG*DEPTH)) eeprom (
        .a({1'b0, rom_addr}), .dq(rom_data), .ce_n(1'b0), .oe_n(1'b0), .we_n(1'b1)
    );

    // --- boot loader: EEPROM -> control store, emits `loading` --------------
    (* purpose = "boot loader (EEPROM to WCS)" *)
    uc_loader loader (
        .clk(clk), .rst_n(rst_n),
        .rom_addr(rom_addr), .rom_data(rom_data),
        .sram_addr(loader_addr), .sram_wdata(loader_wdata),
        .cs_n(cs_sel_n), .loading(loading)
    );

    // --- run = ~loading (release the micro-PC) ------------------------------
    wire [5:0] inv_y;
    (* purpose = "run = ~loading" *)
    sn74ahct04 inv (.a({5'b0, loading}), .y(inv_y));
    assign run = inv_y[0];

    // --- opcode register IR: drives the opcode-LUT dispatch index ----------------
    // Real architectural register (R-HW-4). Until the fetch datapath loads it from memory,
    // its data comes from the `ir_drive` debug tap; it latches every cycle.
    wire [7:0] ir;
    (* purpose = "opcode register IR" *)
    sn74ahct574 ir_reg (.Q(ir), .D(ir_drive), .CLK(clk), .OE_n(1'b0));

    // --- microsequencer: computes the next micro-PC from the sequencer section --
    // lut_data is the opcode-LUT dispatch target (DISPATCH_IR loads it into µPC).
    wire [11:0] lut_data;
    (* purpose = "micro-sequencer (next uPC)" *)
    microsequencer useq (
        .clk(clk), .clr_n(run),
        .useq_op(cw_wcs[2:0]), .next_addr(cw_wcs[14:3]),
        .ucond_sel(cw_wcs[18:15]), .ucond_pol(cw_wcs[19]),
        .cond(cond_drive), .lut_data(lut_data), .upc(upc)
    );

    // --- WCS address mux: SELECT=loading ? loader cnt : micro-PC -------------
    wire [11:0] mux_a = upc;
    wire [11:0] mux_b = loader_addr;
    wire [11:0] mux_y;
    (* purpose = "WCS addr mux [3:0]" *)
    sn74ahct157 m0 (.a(mux_a[3:0]),   .b(mux_b[3:0]),   .sel(loading), .g_n(1'b0), .y(mux_y[3:0]));
    (* purpose = "WCS addr mux [7:4]" *)
    sn74ahct157 m1 (.a(mux_a[7:4]),   .b(mux_b[7:4]),   .sel(loading), .g_n(1'b0), .y(mux_y[7:4]));
    (* purpose = "WCS addr mux [11:8]" *)
    sn74ahct157 m2 (.a(mux_a[11:8]),  .b(mux_b[11:8]),  .sel(loading), .g_n(1'b0), .y(mux_y[11:8]));
    assign cs_addr = mux_y[11:0];

    // --- per-chip /WE strobe: cs_sel_n[g] | clk  (4x '32, clk fanned out) ----
    wire [15:0] we_pad;
    (* purpose = "/WE strobe [3:0]" *)
    sn74ahct32 w0 (.a(cs_sel_n[3:0]),      .b({4{clk}}), .y(we_pad[3:0]));
    (* purpose = "/WE strobe [7:4]" *)
    sn74ahct32 w1 (.a(cs_sel_n[7:4]),      .b({4{clk}}), .y(we_pad[7:4]));
    (* purpose = "/WE strobe [11:8]" *)
    sn74ahct32 w2 (.a(cs_sel_n[11:8]),     .b({4{clk}}), .y(we_pad[11:8]));
    (* purpose = "/WE strobe [12]" *)
    sn74ahct32 w3 (.a({3'b000, cs_sel_n[12]}), .b({4{clk}}), .y(we_pad[15:12]));
    assign we_n = we_pad[12:0];

    // --- control store: 11 WCS chips (the 88-bit word) + 2 opcode-LUT chips --
    // Both blocks share the boot-write path: the EEPROM byte (loader_wdata) gated by run
    // (wbuf_oe_n), SRAM /OE = loading, and their slice of the per-chip /WE strobe.
    wire [87:0] cw_wcs;             // the 88-bit control word (WCS SRAMs 0..10)
    wire [7:0]  lut_lo, lut_hi;     // opcode-LUT bytes (SRAMs 11, 12)

    (* purpose = "WCS (88-bit control word)" *)
    microcode_store #(.NWCS(11)) store (
        .addr(cs_addr), .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .we_n(we_n[10:0]), .cw(cw_wcs)
    );
    (* purpose = "opcode LUT (dispatch)" *)
    opcode_lut lut (
        .loader_addr(loader_addr), .dispatch_page(cw_wcs[22]), .ir(ir), .loading(loading),
        .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .we_n(we_n[12:11]), .lut_lo(lut_lo), .lut_hi(lut_hi)
    );

    // Observation taps: `cw` is the 88-bit control word (WCS only — the LUT bytes are not
    // part of it); `lut_data` (= `lut_out`) is the opcode-LUT's 12-bit dispatch target
    // (low byte + high 4 bits), the value DISPATCH_IR loads into the µPC.
    assign cw       = cw_wcs;
    assign lut_data = {lut_hi[3:0], lut_lo};
    assign lut_out  = lut_data;

    // --- control-word decoder: datapath section -> one-hot datapath strobes --
    // The 64-bit datapath section is cw[87:24]. The strobes drive nothing yet (the datapath
    // does not exist — hardware.md §2), so they are observed hierarchically (dut.dec.*) as
    // privileged debug taps (R-DBG-5) until the datapath consumes them.
    (* purpose = "datapath decoder" *)
    control_word_decoder dec (.cw_dp(cw_wcs[87:24]));
endmodule
`default_nettype wire
