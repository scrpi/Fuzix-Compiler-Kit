// microcode_store — the writable control store (WCS): the 11 byte-wide SRAMs that hold
// the 88-bit horizontal control word, plus their address mux and boot-write path.
// Structural netlist of real chips (R-SIM-1, R-SIM-5; microcode.md §3, hardware.md §4).
//
// A self-contained boot-loadable memory (the same shape as opcode_lut): it picks its own
// address — the running micro-PC (`upc`) or, during boot, the loader counter (`loader_addr`)
// — and reads one 88-bit control word out, byte k = SRAM k. During boot the same chips are
// written: the loader fans the EEPROM byte onto every SRAM's I/O through a per-chip
// isolation buffer, and the block strobes one chip's /WE at a time (formed here from the
// loader's per-chip select and the clock, so the byte latches with the address stable).
//
// Structure (the BOM):
//   3x sn74ahct157  -> the 12-bit address mux (SEL = loading ? loader_addr : upc).
//   3x sn74ahct32   -> the per-chip /WE strobe (cs_n[g] | clk; one gate spare over 11 chips).
//   11x sn74ahct541 -> per-SRAM boot-write isolation buffer. Enabled (oe1_n=wbuf_oe_n=run,
//                      LOW in boot) to drive the shared EEPROM byte onto that SRAM's I/O
//                      during the copy; tri-stated in run so the SRAM drives its own byte.
//   11x is61c64     -> the WCS SRAMs (8 K part, A12 grounded -> 4096-word store, D-49). /CE
//                      tied low; /OE = oe_n (= loading: write in boot, read in run); /WE the
//                      per-chip strobe formed above.
`timescale 1ns/1ps
`default_nettype none
// NWCS names the word width (11 bytes = the 88-bit word) for the port/array widths below,
// but it is a FIXED geometry constant, not a free knob: the internal address mux (3x '157,
// 12-bit) and the /WE strobe bank (3x '32, wired literally as cs_n[3:0]/[7:4]/{0,cs_n[10:8]})
// are hard-wired for exactly 11 chips and the 4096-word depth. Changing NWCS would resize the
// SRAM array and ports but NOT re-wire the mux/strobe, so it must stay 11.
module microcode_store #(
    parameter NWCS = 11             // word width in bytes (88-bit control word); fixed — see note above
) (
    input  wire             clk,        // /WE strobe clock phase (the write pulse rises at posedge)
    input  wire [11:0]      upc,        // run address: the micro-PC
    input  wire [11:0]      loader_addr,// boot address: the loader counter
    input  wire             loading,    // 1 = boot (loader_addr), 0 = run (upc)
    input  wire [7:0]       wdata,      // boot write data (= the EEPROM byte)
    input  wire             wbuf_oe_n,  // boot-write buffer enable, active LOW (= run)
    input  wire             oe_n,       // SRAM /OE, active LOW (= loading)
    input  wire [NWCS-1:0]  cs_n,       // per-chip select, active LOW (from the loader)
    output wire [8*NWCS-1:0] cw          // the 88-bit control word (byte k = SRAM k)
);
    // ---- address mux: run = upc, boot = loader_addr (SEL = loading) ---------
    wire [11:0] addr;
    (* purpose = "WCS addr mux [3:0]" *)
    sn74ahct157 a0 (.a(upc[3:0]),   .b(loader_addr[3:0]),   .sel(loading), .g_n(1'b0), .y(addr[3:0]));
    (* purpose = "WCS addr mux [7:4]" *)
    sn74ahct157 a1 (.a(upc[7:4]),   .b(loader_addr[7:4]),   .sel(loading), .g_n(1'b0), .y(addr[7:4]));
    (* purpose = "WCS addr mux [11:8]" *)
    sn74ahct157 a2 (.a(upc[11:8]),  .b(loader_addr[11:8]),  .sel(loading), .g_n(1'b0), .y(addr[11:8]));

    // ---- per-chip /WE strobe: cs_n[g] | clk  (3x '32; one gate spare) -------
    // For the selected chip (cs_n[g] LOW) /WE pulses LOW while clk is LOW and rises at the
    // next posedge, latching the byte with the address stable; HIGH otherwise (no write).
    wire [11:0] we_pad;
    (* purpose = "/WE strobe [3:0]" *)
    sn74ahct32 ws0 (.a(cs_n[3:0]),          .b({4{clk}}), .y(we_pad[3:0]));
    (* purpose = "/WE strobe [7:4]" *)
    sn74ahct32 ws1 (.a(cs_n[7:4]),          .b({4{clk}}), .y(we_pad[7:4]));
    (* purpose = "/WE strobe [10:8]" *)
    sn74ahct32 ws2 (.a({1'b0, cs_n[10:8]}), .b({4{clk}}), .y(we_pad[11:8]));
    wire [NWCS-1:0] we_n = we_pad[NWCS-1:0];

    // ---- the 11 WCS SRAMs + their boot-write buffers ------------------------
    wire [7:0] io [0:NWCS-1];
    genvar g;
    generate for (g = 0; g < NWCS; g = g + 1) begin : chip
        sn74ahct541 wbuf (.a(wdata), .oe1_n(wbuf_oe_n), .oe2_n(1'b0), .y(io[g]));
        is61c64 #(.AW(13), .DW(8)) sram (
            .a({1'b0, addr}), .io(io[g]), .ce_n(1'b0), .oe_n(oe_n), .we_n(we_n[g])
        );
        assign cw[8*g +: 8] = io[g];
    end endgenerate
endmodule
`default_nettype wire
