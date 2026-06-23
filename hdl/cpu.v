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
//   uc_loader       -> the boot loader: owns the microcode EEPROM (param FILE) and copies
//                      it into the control store at power-on; emits `loading`.
//   sn74ahct04      -> run = ~loading (releases the micro-PC).
//   microsequencer  -> the real 12-bit micro-PC: INC/JUMP/BRANCH/WAIT/DISPATCH_IR (it reads
//                      the control word's sequencer section + the conditions + the LUT).
//   sn74ahct574     -> the 8-bit opcode register IR (drives the opcode-LUT dispatch index).
//   microcode_store -> the 11 WCS SRAMs (88-bit control word) + their own address mux and
//                      boot-write path: run-addressed by the micro-PC, boot by the loader.
//   opcode_lut      -> the 2 opcode->start-address LUT SRAMs + their own address mux and
//                      boot-write path: run-addressed by {PAGE, IR}, boot by the loader.
//   control_word_decoder -> the datapath section's one-hot strobes (observation only).
//
// SCAFFOLD: the datapath that would drive IR (from a memory fetch) and the condition lines
// (from CC/flags) does not exist yet (hardware.md §2), so the bench injects them via the
// `ir_drive` / `cond_drive` debug taps. CALL/RETURN, the ULOOP loop counter, the trap-vector
// encoder, and the registered (pipelined) control word are deferred (microsequencer.v).
`timescale 1ns/1ps
`default_nettype none
module cpu #(
    parameter FILE = ""              // the microcode image (burned into the loader's EEPROM)
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

    wire [11:0]     loader_addr;     // loader's control-store address during boot
    wire [7:0]      loader_wdata;    // loader's boot write data (= the EEPROM byte)
    wire [NSEG-1:0] cs_sel_n;        // per-chip select (active low) from the loader
    wire            run;             // = ~loading

    // --- boot loader: owns the microcode EEPROM, copies it -> control store --
    (* purpose = "microcode loader" *)
    uc_loader #(.FILE(FILE)) loader (
        .clk(clk), .rst_n(rst_n),
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

    // --- control store: 11 WCS chips (the 88-bit word) + 2 opcode-LUT chips --
    // Each block is a self-contained boot-loadable memory: it takes the loader address, its
    // own run address, and `loading`, and muxes the address internally; it also forms its
    // own per-chip /WE (cs_n[g] | clk) from its slice of the loader's selects. The only
    // shared boot-write signals are the EEPROM byte (loader_wdata, gated by run via
    // wbuf_oe_n) and the SRAM /OE (= loading).
    wire [87:0] cw_wcs;             // the 88-bit control word (WCS SRAMs 0..10)
    wire [7:0]  lut_lo, lut_hi;     // opcode-LUT bytes (SRAMs 11, 12)

    (* purpose = "WCS (88-bit control word)" *)
    microcode_store #(.NWCS(11)) store (
        .clk(clk), .upc(upc), .loader_addr(loader_addr), .loading(loading),
        .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .cs_n(cs_sel_n[10:0]), .cw(cw_wcs)
    );
    (* purpose = "opcode LUT (dispatch)" *)
    opcode_lut lut (
        .clk(clk), .loader_addr(loader_addr), .dispatch_page(cw_wcs[22]), .ir(ir), .loading(loading),
        .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .cs_n(cs_sel_n[12:11]), .lut_lo(lut_lo), .lut_hi(lut_hi)
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
